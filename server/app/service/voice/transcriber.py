"""Vietnamese speech-to-text: VinAI's PhoWhisper runs on the Kaggle GPU (notebooks/kaggle_ollama.py).

PhoWhisper-medium/large is too slow on a laptop CPU, so the server only uploads the audio through
the notebook's Cloudflare tunnel. The notebook prints ASR_BASE_URL, ASR_TOKEN and PHOWHISPER_MODEL.
"""

import logging
import os
import time
from dataclasses import dataclass
from threading import Lock

import httpx

DEFAULT_MODEL_NAME = os.getenv("PHOWHISPER_MODEL", "vinai/PhoWhisper-medium")
DEFAULT_BASE_URL = os.getenv("ASR_BASE_URL", "")
DEFAULT_TOKEN = os.getenv("ASR_TOKEN", "")
DEFAULT_TIMEOUT_SECONDS = float(os.getenv("ASR_TIMEOUT_SECONDS", "120"))

logger = logging.getLogger(__name__)


class AsrUnavailable(RuntimeError):
    """Kaggle is down, unreachable or misconfigured: keep the recording and try again later."""


class AsrRejected(RuntimeError):
    """The speech server refused the audio itself (cannot decode): retrying will not help."""


@dataclass
class TranscriptionResult:
    """Text recognized from one audio file, plus how long recognition took."""

    text: str
    duration_seconds: float


class PhoWhisperTranscriber:
    """Sends audio files to the PhoWhisper server on Kaggle and returns the Vietnamese text."""

    _instance: "PhoWhisperTranscriber | None" = None
    _instance_lock = Lock()

    def __init__(self, base_url: str = DEFAULT_BASE_URL, token: str = DEFAULT_TOKEN,
                 model_name: str = DEFAULT_MODEL_NAME, http: httpx.Client | None = None):
        """Keep one HTTP client to the notebook; fail early when the notebook URL is missing."""
        if not base_url and http is None:
            raise AsrUnavailable("ASR_BASE_URL is not set: run notebooks/kaggle_ollama on Kaggle first")
        self.model_name = model_name
        # The token stops strangers who find the public tunnel URL from using the GPU.
        self._http = http or httpx.Client(base_url=base_url.rstrip("/"), timeout=DEFAULT_TIMEOUT_SECONDS,
                                          headers={"Authorization": f"Bearer {token}"})

    @classmethod
    def get_instance(cls) -> "PhoWhisperTranscriber":
        """Return the shared transcriber, creating it on first use (thread-safe)."""
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    def transcribe_file(self, audio_path: str) -> TranscriptionResult:
        """Upload the raw audio bytes (the notebook decodes them with ffmpeg) and return the text."""
        with open(audio_path, "rb") as audio_file:
            audio_bytes = audio_file.read()
        start, host = time.perf_counter(), self._http.base_url.host
        try:
            response = self._http.post("/transcribe", content=audio_bytes,
                                       headers={"Content-Type": "application/octet-stream"})
            response.raise_for_status()
            text = response.json()["text"].strip()
        except httpx.HTTPStatusError as error:
            logger.warning("ASR via %s failed: HTTP %d", host, error.response.status_code)
            # No URL in the message: it reaches the app and would leak the tunnel address.
            error_type = AsrRejected if error.response.status_code == 400 else AsrUnavailable
            raise error_type(f"speech server returned HTTP {error.response.status_code}") from error
        except (httpx.HTTPError, ValueError, KeyError) as error:
            logger.warning("ASR via %s unreachable: %s", host, error)
            raise AsrUnavailable("speech server is unreachable") from error
        elapsed = time.perf_counter() - start
        logger.info("ASR via %s ok in %.0fms", host, elapsed * 1000)
        return TranscriptionResult(text=text, duration_seconds=round(elapsed, 2))
