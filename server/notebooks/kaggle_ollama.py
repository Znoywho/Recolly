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
# # Recolly: Ollama on Kaggle (12B model)
#
# Runs an Ollama server on Kaggle's GPUs and exposes it through a Cloudflare tunnel so the Recolly backend can call it.
#
# **Before running** (right sidebar, *Session options*):
# - Accelerator: **GPU T4 x2**
# - Internet: **On** (needs a phone-verified Kaggle account)
#
# Then *Run All*. The last cells print the public URL to put in the server's `.env`.
#
# **Warning:** Ollama has no authentication. Anyone with the tunnel URL can use the model, so stop the session when the demo is over.

# %% [markdown]
# ## 1. Settings

# %%
# Models to pull. The first one is the main (large) model.
# Add a second, smaller one for JSON extraction, e.g. "qwen2.5:7b".
MODEL_NAMES = ["gemma3:12b"]

OLLAMA_PORT = 11434
OLLAMA_URL = f"http://localhost:{OLLAMA_PORT}"
OLLAMA_LOG_PATH = "/kaggle/working/ollama.log"
TUNNEL_LOG_PATH = "/kaggle/working/cloudflared.log"

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
# ## 7. Open the public tunnel

# %%
import re

!wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /kaggle/working/cloudflared
!chmod +x /kaggle/working/cloudflared


def start_tunnel() -> subprocess.Popen:
    """Start a Cloudflare quick tunnel that forwards to the Ollama port."""
    log_file = open(TUNNEL_LOG_PATH, "w")
    command = [
        "/kaggle/working/cloudflared", "tunnel",
        "--url", OLLAMA_URL,
        "--http-host-header", f"localhost:{OLLAMA_PORT}",
    ]
    return subprocess.Popen(command, stdout=log_file, stderr=log_file)


def wait_for_tunnel_url(timeout_seconds: int = 60) -> str:
    """Read the tunnel log until the public trycloudflare.com URL appears."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        with open(TUNNEL_LOG_PATH) as log_file:
            match = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", log_file.read())
        if match:
            return match.group(0)
        time.sleep(1)
    raise RuntimeError(f"No tunnel URL found, see {TUNNEL_LOG_PATH}")


tunnel_process = start_tunnel()
public_url = wait_for_tunnel_url()

print("Put these lines in the Recolly server .env:\n")
print(f"OLLAMA_BASE_URL={public_url}")
print(f"OLLAMA_MODEL={MODEL_NAMES[0]}")


# %% [markdown]
# ## 8. Keep the session alive
#
# Leave this cell running during the demo. It prints a heartbeat every minute and stops with an error if Ollama or the tunnel dies. Interrupt it (stop button) when you are done, then stop the session.

# %%
def keep_session_alive(check_interval_seconds: int = 60) -> None:
    """Print a heartbeat forever and raise if the server or the tunnel has stopped."""
    while True:
        if ollama_process.poll() is not None:
            raise RuntimeError(f"Ollama stopped, see {OLLAMA_LOG_PATH}")
        if tunnel_process.poll() is not None:
            raise RuntimeError(f"Tunnel stopped, see {TUNNEL_LOG_PATH}")
        print(time.strftime("%H:%M:%S"), "alive:", public_url)
        time.sleep(check_interval_seconds)


keep_session_alive()
