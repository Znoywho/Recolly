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
# # Recolly: Ollama + PhoWhisper on Kaggle
#
# Runs an Ollama server (LLM) and a PhoWhisper speech-to-text server on Kaggle's GPUs and exposes both through Cloudflare tunnels so the Recolly backend can call them. PhoWhisper is too slow on a laptop CPU, so the backend has no local speech model.
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
# ## 7. Start the PhoWhisper speech server
#
# A small HTTP server (standard library only) on its own GPU: `POST /transcribe` takes the raw audio bytes with `Authorization: Bearer <ASR_TOKEN>` and returns `{"text": ...}`; `GET /health` answers without a token. The first start downloads the model (about 1.5 GB for medium).

# %%
import secrets
import shutil

if shutil.which("ffmpeg") is None:  # decodes the uploaded phone audio
    subprocess.run("apt-get -qq update && apt-get -qq install -y ffmpeg > /dev/null", shell=True, check=True)

ASR_SERVER_CODE = r"""
import hmac
import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import torch
import transformers
from transformers import pipeline

MODEL_NAME = os.environ["ASR_MODEL"]
TOKEN = os.environ["ASR_TOKEN"]
SAMPLE_RATE = 16_000  # Whisper models expect 16 kHz mono audio
MAX_AUDIO_BYTES = 25 * 1024 * 1024  # same limit as the backend

dtype_name = "dtype" if int(transformers.__version__.split(".")[0]) >= 5 else "torch_dtype"
asr = pipeline("automatic-speech-recognition", model=MODEL_NAME, device=0, chunk_length_s=30,
               **{dtype_name: torch.float16})
gpu_lock = threading.Lock()  # one GPU: transcribe one file at a time


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
    '''GET /health and POST /transcribe.'''

    def do_GET(self):
        '''Health check, no token needed.'''
        if self.path == "/health":
            self.reply(200, {"status": "ok", "model": MODEL_NAME})
        else:
            self.reply(404, {"error": "not found"})

    def do_POST(self):
        '''Check the token and size, decode the audio, return the Vietnamese transcript.'''
        if self.path != "/transcribe":
            return self.reply(404, {"error": "not found"})
        if not hmac.compare_digest(self.headers.get("Authorization", ""), f"Bearer {TOKEN}"):
            return self.reply(401, {"error": "bad token"})
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= MAX_AUDIO_BYTES:
            return self.reply(413, {"error": "audio must be 1 byte to 25 MB"})
        try:
            waveform = decode_audio(self.rfile.read(length))
        except subprocess.CalledProcessError:
            return self.reply(400, {"error": "cannot decode audio"})
        with gpu_lock:
            output = asr({"raw": waveform, "sampling_rate": SAMPLE_RATE},
                         generate_kwargs={"language": "vi", "task": "transcribe"})
        self.reply(200, {"text": output["text"].strip()})

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
                       ASR_TOKEN=ASR_TOKEN, ASR_PORT=str(ASR_PORT))
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
print(f"Speech server is running ({ASR_MODEL_NAME})")

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
