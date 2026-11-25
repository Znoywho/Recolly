# ---
# jupyter:
#   jupytext:
#     text_representation:
#       extension: .py
#       format_name: hydrogen
#       format_version: '1.3'
#       jupytext_version: 1.19.6
#   kernelspec:
#     display_name: Python 3
#     language: python
#     name: python3
# ---

# %% [markdown]
# # Recolly: Ollama + PhoWhisper + Vintern on Kaggle
#
# Runs an Ollama server (LLM) and an AI server with PhoWhisper (speech-to-text) and Vintern (timetable photo OCR) on Kaggle's GPUs, and exposes both through Cloudflare tunnels so the Recolly backend can call them. These models are too slow on a laptop CPU, so the backend has no local model.
#
# **Before running** (right sidebar, *Session options*):
# - Accelerator: **GPU T4 x2**
# - Internet: **On** (needs a phone-verified Kaggle account)
#
# Then *Run All*. The last cells print the public URL to put in the server's `.env`.
#
# **Warning:** Ollama has no authentication. Anyone with the tunnel URL can use the model, so stop the session when the demo is over. The speech server checks a random token made each session (`ASR_TOKEN`). Never commit this notebook with its outputs: they contain the URLs and the token.

# %% [markdown]
# ## 1. Settings

# %%
# Models to pull. The first one is the main (large) model.
# Add a second, smaller one for JSON extraction, e.g. "qwen2.5:7b".
MODEL_NAMES = ["qwen2.5:14b"]  # chosen in kaggle_voice_eval.ipynb: best TSR on real audio with A2a repair

OLLAMA_PORT = 11434
OLLAMA_URL = f"http://localhost:{OLLAMA_PORT}"
OLLAMA_LOG_PATH = "/kaggle/working/ollama.log"
TUNNEL_LOG_PATH = "/kaggle/working/cloudflared.log"

# Speech-to-text. medium: best deadline accuracy in kaggle_voice_eval (0.968), faster than large.
ASR_MODEL_NAME = "vinai/PhoWhisper-medium"
ASR_PORT = 8001
ASR_GPU = "1"  # second T4; Ollama keeps its model on the first one
ASR_SERVER_PATH = "/kaggle/working/asr_server.py"
ASR_LOG_PATH = "/kaggle/working/asr_server.log"
ASR_TUNNEL_LOG_PATH = "/kaggle/working/cloudflared_asr.log"

# Timetable OCR, served by the same process, GPU, tunnel and token as speech (POST /ocr).
# Model card: https://huggingface.co/5CD-AI/Vintern-1B-v3_5 (license CC BY-NC 4.0: non-commercial use only).
OCR_MODEL_NAME = "5CD-AI/Vintern-1B-v3_5"
# The T4 has no native bfloat16 (the card's dtype), so float16. If the OCR text comes out empty or garbled, try "bfloat16".
OCR_DTYPE = "float16"

# %% [markdown]
# ## 2. Check the GPUs
# You should see two Tesla T4 cards with about 15 GB each.

# %%
!nvidia-smi --query-gpu=index,name,memory.total,memory.used --format=csv

# %% [markdown]
# ## 3. Install Ollama

# %%
!apt-get install -y -qq zstd > /dev/null
!curl -fsSL https://ollama.com/install.sh | sh
!ollama --version

# %% [markdown]
# ## 4. Start the Ollama server

# %%
import json
import os
import subprocess
import time
import urllib.request


def start_ollama_server() -> subprocess.Popen:
    """Start `ollama serve` in the background, writing its output to a log file."""
    environment = dict(os.environ)
    environment["OLLAMA_HOST"] = f"0.0.0.0:{OLLAMA_PORT}"
    environment["OLLAMA_MAX_LOADED_MODELS"] = str(len(MODEL_NAMES))  # keep every model in VRAM
    environment["OLLAMA_KEEP_ALIVE"] = "-1"  # never unload a model between requests
    log_file = open(OLLAMA_LOG_PATH, "w")
    return subprocess.Popen(["ollama", "serve"], env=environment, stdout=log_file, stderr=log_file)


def wait_until_server_is_ready(timeout_seconds: int = 60) -> None:
    """Poll GET /api/tags until the server answers, or fail after the timeout."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f"{OLLAMA_URL}/api/tags", timeout=2)
            return
        except OSError:
            time.sleep(1)
    raise RuntimeError(f"Ollama did not start, see {OLLAMA_LOG_PATH}")


ollama_process = start_ollama_server()
wait_until_server_is_ready()
print("Ollama server is running")

# %% [markdown]
# ## 5. Pull the models
# `gemma3:12b` is about 8 GB, so this takes a few minutes on every new session.

# %%
for model_name in MODEL_NAMES:
    print(f"Pulling {model_name} ...")
    subprocess.run(["ollama", "pull", model_name], check=True)

!ollama list


# %% [markdown]
# ## 6. Load the models and test them in Vietnamese
# The first call loads the model into VRAM (slow); later calls are fast.

# %%
def send_chat_request(model_name: str, system_prompt: str, user_message: str) -> str:
    """Call POST /api/chat on the local server and return the reply text."""
    payload = {
        "model": model_name,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "stream": False,
    }
    request = urllib.request.Request(
        f"{OLLAMA_URL}/api/chat",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=600) as response:
        return json.loads(response.read())["message"]["content"].strip()


TEST_SYSTEM_PROMPT = (
    'Bạn là Recolly. Tính cách: bạn thân hay cà khịa nhẹ. '
    'Người dùng đang nợ 3.5 giờ ngủ. Deadline gần nhất: Báo cáo AI, 9 giờ sáng mai. '
    'Viết đúng 1 câu động viên bằng tiếng Việt, xưng "tui", gọi "bạn". Chỉ trả về câu đó.'
)

for model_name in MODEL_NAMES:
    start_time = time.time()
    reply = send_chat_request(model_name, TEST_SYSTEM_PROMPT, "Cho tui một câu đi.")
    print(f"[{model_name}] ({time.time() - start_time:.1f}s) {reply}")

!ollama ps
!nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv

# %% [markdown]
# ## 7. Start the AI server (PhoWhisper + Vintern)
#
# A small HTTP server (standard library only) on its own GPU. With `Authorization: Bearer <ASR_TOKEN>`: `POST /transcribe` takes raw audio bytes and `POST /ocr` takes a timetable photo (JPEG/PNG/HEIC, max 10 MB); both return `{"text": ...}` (OCR text is a markdown table). `GET /health` answers without a token. The first start downloads both models (about 1.5 GB + 2 GB).
#
# Vintern loads custom model code from Hugging Face (`trust_remote_code`). If loading fails with a transformers error, see `asr_server.log`; pinning an older transformers in a new cell (e.g. `!pip install -q "transformers<5"`), then restarting the session, is the first thing to try.

# %%
import secrets
import shutil

if shutil.which("ffmpeg") is None:  # decodes the uploaded phone audio
    subprocess.run("apt-get -qq update && apt-get -qq install -y ffmpeg > /dev/null", shell=True, check=True)
# Vintern's remote code needs timm + einops; pillow-heif opens iPhone HEIC photos.
subprocess.run("pip install -q timm einops pillow-heif", shell=True, check=True)

ASR_SERVER_CODE = r"""
import hmac
import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import io

import numpy as np
import torch
import torchvision.transforms as T
import transformers
from PIL import Image, UnidentifiedImageError
from pillow_heif import register_heif_opener
from torchvision.transforms.functional import InterpolationMode
from transformers import AutoModel, AutoTokenizer, pipeline

MODEL_NAME = os.environ["ASR_MODEL"]
OCR_MODEL_NAME = os.environ["OCR_MODEL"]
TOKEN = os.environ["ASR_TOKEN"]
SAMPLE_RATE = 16_000  # Whisper models expect 16 kHz mono audio
MAX_AUDIO_BYTES = 25 * 1024 * 1024  # same limit as the backend
MAX_IMAGE_BYTES = 10 * 1024 * 1024  # same limit as the backend
TILE_SIZE = 448  # Vintern (InternVL) sees the photo as 448 x 448 tiles
MAX_TILES = 6    # the model card uses up to 6 tiles per image
IMAGENET_MEAN, IMAGENET_STD = (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)
OCR_PROMPT = ("<image>\nTrích xuất toàn bộ bảng thời khoá biểu trong ảnh thành bảng markdown. Giữ nguyên thứ, "
              "tiết hoặc giờ học, tên môn, mã môn, phòng, giảng viên, ngày bắt đầu và kết thúc.")
OCR_GENERATION = dict(max_new_tokens=1024, do_sample=False, num_beams=3, repetition_penalty=2.5)  # model card values

dtype_name = "dtype" if int(transformers.__version__.split(".")[0]) >= 5 else "torch_dtype"
asr = pipeline("automatic-speech-recognition", model=MODEL_NAME, device=0, chunk_length_s=30,
               **{dtype_name: torch.float16})
ocr_dtype = getattr(torch, os.environ["OCR_DTYPE"])
ocr_model = AutoModel.from_pretrained(OCR_MODEL_NAME, low_cpu_mem_usage=True, trust_remote_code=True,
                                      use_flash_attn=False, **{dtype_name: ocr_dtype}).eval().cuda()
ocr_tokenizer = AutoTokenizer.from_pretrained(OCR_MODEL_NAME, trust_remote_code=True, use_fast=False)
to_tensor = T.Compose([T.Resize((TILE_SIZE, TILE_SIZE), interpolation=InterpolationMode.BICUBIC),
                       T.ToTensor(), T.Normalize(IMAGENET_MEAN, IMAGENET_STD)])
register_heif_opener()
gpu_lock = threading.Lock()  # one GPU: run one model call at a time


def decode_image(image_bytes: bytes) -> Image.Image:
    '''Open a JPEG/PNG/HEIC photo as RGB (raises UnidentifiedImageError for anything else).'''
    return Image.open(io.BytesIO(image_bytes)).convert("RGB")


def split_into_tiles(image: Image.Image) -> list:
    '''InternVL dynamic preprocessing (model card): up to MAX_TILES tiles in the grid closest to the
    photo's aspect ratio, plus a whole-photo thumbnail when there is more than one tile.'''
    width, height = image.size
    grids = sorted({(c, r) for c in range(1, MAX_TILES + 1) for r in range(1, MAX_TILES + 1) if c * r <= MAX_TILES},
                   key=lambda grid: grid[0] * grid[1])
    best, best_diff = (1, 1), float("inf")
    for columns, rows in grids:
        diff = abs(width / height - columns / rows)
        # On a tie, a bigger grid only if the photo has enough pixels to fill it.
        if diff < best_diff or (diff == best_diff and width * height > 0.5 * TILE_SIZE ** 2 * columns * rows):
            best, best_diff = (columns, rows), diff
    columns, rows = best
    resized = image.resize((columns * TILE_SIZE, rows * TILE_SIZE))
    tiles = [resized.crop(((i % columns) * TILE_SIZE, (i // columns) * TILE_SIZE,
                           (i % columns + 1) * TILE_SIZE, (i // columns + 1) * TILE_SIZE))
             for i in range(columns * rows)]
    if len(tiles) > 1:
        tiles.append(image.resize((TILE_SIZE, TILE_SIZE)))
    return tiles


def read_timetable(image: Image.Image) -> str:
    '''Ask Vintern for the timetable in the photo as markdown.'''
    pixel_values = torch.stack([to_tensor(tile) for tile in split_into_tiles(image)]).to(ocr_dtype).cuda()
    with gpu_lock:
        return ocr_model.chat(ocr_tokenizer, pixel_values, OCR_PROMPT, OCR_GENERATION).strip()


def decode_audio(audio_bytes: bytes) -> np.ndarray:
    '''Decode any audio file to a 16 kHz mono float32 waveform with ffmpeg.

    Goes through a temp file: phone .m4a files keep their index at the end, which a pipe cannot seek to.
    '''
    with tempfile.NamedTemporaryFile() as audio_file:
        audio_file.write(audio_bytes)
        audio_file.flush()
        output = subprocess.run(["ffmpeg", "-v", "error", "-i", audio_file.name, "-f", "f32le", "-ac", "1",
                                 "-ar", str(SAMPLE_RATE), "-"], capture_output=True, check=True)
    return np.frombuffer(output.stdout, dtype=np.float32).copy()


class AsrHandler(BaseHTTPRequestHandler):
    '''GET /health, POST /transcribe (audio) and POST /ocr (timetable photo).'''

    def do_GET(self):
        '''Health check, no token needed.'''
        if self.path == "/health":
            self.reply(200, {"status": "ok", "model": MODEL_NAME, "ocr_model": OCR_MODEL_NAME})
        else:
            self.reply(404, {"error": "not found"})

    def do_POST(self):
        '''Check the path, token and size, then run speech-to-text or OCR.'''
        limits = {"/transcribe": MAX_AUDIO_BYTES, "/ocr": MAX_IMAGE_BYTES}
        if self.path not in limits:
            return self.reply(404, {"error": "not found"})
        if not hmac.compare_digest(self.headers.get("Authorization", ""), f"Bearer {TOKEN}"):
            return self.reply(401, {"error": "bad token"})
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= limits[self.path]:
            return self.reply(413, {"error": f"body must be 1 byte to {limits[self.path] // 2**20} MB"})
        body = self.rfile.read(length)
        if self.path == "/ocr":
            return self.answer_ocr(body)
        try:
            waveform = decode_audio(body)
        except subprocess.CalledProcessError:
            return self.reply(400, {"error": "cannot decode audio"})
        with gpu_lock:
            output = asr({"raw": waveform, "sampling_rate": SAMPLE_RATE},
                         generate_kwargs={"language": "vi", "task": "transcribe"})
        self.reply(200, {"text": output["text"].strip()})

    def answer_ocr(self, image_bytes: bytes) -> None:
        '''Decode the photo and return Vintern's markdown table.'''
        try:
            image = decode_image(image_bytes)
        except (UnidentifiedImageError, OSError):
            return self.reply(400, {"error": "cannot open image"})
        self.reply(200, {"text": read_timetable(image), "model": OCR_MODEL_NAME})

    def reply(self, status: int, body: dict) -> None:
        '''Send a JSON response.'''
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


ThreadingHTTPServer(("0.0.0.0", int(os.environ["ASR_PORT"])), AsrHandler).serve_forever()
"""

ASR_TOKEN = secrets.token_urlsafe(24)  # new every session


def start_asr_server() -> subprocess.Popen:
    """Write the speech server script and run it in the background on its own GPU."""
    with open(ASR_SERVER_PATH, "w") as script_file:
        script_file.write(ASR_SERVER_CODE)
    environment = dict(os.environ, CUDA_VISIBLE_DEVICES=ASR_GPU, ASR_MODEL=ASR_MODEL_NAME,
                       OCR_MODEL=OCR_MODEL_NAME, OCR_DTYPE=OCR_DTYPE, ASR_TOKEN=ASR_TOKEN, ASR_PORT=str(ASR_PORT))
    log_file = open(ASR_LOG_PATH, "w")
    return subprocess.Popen(["python", ASR_SERVER_PATH], env=environment, stdout=log_file, stderr=log_file)


def wait_until_asr_is_ready(timeout_seconds: int = 600) -> None:
    """Poll GET /health until the model is loaded, or fail after the timeout."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if asr_process.poll() is not None:
            raise RuntimeError(f"Speech server crashed, see {ASR_LOG_PATH}")
        try:
            urllib.request.urlopen(f"http://localhost:{ASR_PORT}/health", timeout=2)
            return
        except OSError:
            time.sleep(2)
    raise RuntimeError(f"Speech server did not start, see {ASR_LOG_PATH}")


asr_process = start_asr_server()
wait_until_asr_is_ready()
print(f"AI server is running ({ASR_MODEL_NAME} + {OCR_MODEL_NAME})")

# %% [markdown]
# ## 8. Open the public tunnels

# %%
import re

!wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /kaggle/working/cloudflared
!chmod +x /kaggle/working/cloudflared


def start_tunnel(port: int, log_path: str) -> subprocess.Popen:
    """Start a Cloudflare quick tunnel that forwards to a local port."""
    log_file = open(log_path, "w")
    command = [
        "/kaggle/working/cloudflared", "tunnel",
        "--url", f"http://localhost:{port}",
        "--http-host-header", f"localhost:{port}",  # Ollama rejects other Host headers
    ]
    return subprocess.Popen(command, stdout=log_file, stderr=log_file)


def wait_for_tunnel_url(log_path: str, timeout_seconds: int = 60) -> str:
    """Read the tunnel log until the public trycloudflare.com URL appears."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        with open(log_path) as log_file:
            match = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", log_file.read())
        if match:
            return match.group(0)
        time.sleep(1)
    raise RuntimeError(f"No tunnel URL found, see {log_path}")


tunnel_process = start_tunnel(OLLAMA_PORT, TUNNEL_LOG_PATH)
public_url = wait_for_tunnel_url(TUNNEL_LOG_PATH)
asr_tunnel_process = start_tunnel(ASR_PORT, ASR_TUNNEL_LOG_PATH)
asr_public_url = wait_for_tunnel_url(ASR_TUNNEL_LOG_PATH)

print("Put these lines in the Recolly server .env, then: docker compose restart server\n")
print(f"OLLAMA_BASE_URL={public_url}")
print(f"OLLAMA_MODEL={MODEL_NAMES[0]}")
print(f"ASR_BASE_URL={asr_public_url}")
print(f"ASR_TOKEN={ASR_TOKEN}")
print(f"PHOWHISPER_MODEL={ASR_MODEL_NAME}")
print("# OCR (Vintern) uses the same ASR_BASE_URL and ASR_TOKEN")


# %% [markdown]
# ## 9. Keep the session alive
#
# Leave this cell running during the demo. It prints a heartbeat every minute and stops with an error if Ollama, the speech server or a tunnel dies. Interrupt it (stop button) when you are done, then stop the session.

# %%
def keep_session_alive(check_interval_seconds: int = 60) -> None:
    """Print a heartbeat forever and raise if the server or the tunnel has stopped."""
    while True:
        if ollama_process.poll() is not None:
            raise RuntimeError(f"Ollama stopped, see {OLLAMA_LOG_PATH}")
        if tunnel_process.poll() is not None:
            raise RuntimeError(f"Tunnel stopped, see {TUNNEL_LOG_PATH}")
        if asr_process.poll() is not None:
            raise RuntimeError(f"Speech server stopped, see {ASR_LOG_PATH}")
        if asr_tunnel_process.poll() is not None:
            raise RuntimeError(f"Speech tunnel stopped, see {ASR_TUNNEL_LOG_PATH}")
        print(time.strftime("%H:%M:%S"), "alive:", public_url, asr_public_url)
        time.sleep(check_interval_seconds)


keep_session_alive()
