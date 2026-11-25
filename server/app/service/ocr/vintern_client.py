"""Timetable photo → markdown: Vintern-1B-v3_5 runs on the Kaggle GPU (notebooks/kaggle_ollama.py).

It shares the speech server's process, tunnel and token, so it uses ASR_BASE_URL and ASR_TOKEN.
shortcut: the ASR_ names also cover OCR; rename them if the OCR server is ever split out.
"""

import logging
import os
import time
from threading import Lock

import httpx

DEFAULT_BASE_URL = os.getenv("ASR_BASE_URL", "")
DEFAULT_TOKEN = os.getenv("ASR_TOKEN", "")
DEFAULT_TIMEOUT_SECONDS = float(os.getenv("OCR_TIMEOUT_SECONDS", "180"))  # num_beams=3 on a T4 is slow

logger = logging.getLogger(__name__)


class OcrUnavailable(RuntimeError):
    """Kaggle is down, unreachable or not configured."""


class OcrRejected(RuntimeError):
    """The OCR server could not open the image itself: retrying will not help."""


class VinternClient:
    """Sends a timetable photo to the Vintern server on Kaggle and returns the table as markdown."""

    _instance: "VinternClient | None" = None
    _instance_lock = Lock()

    def __init__(self, base_url: str = DEFAULT_BASE_URL, token: str = DEFAULT_TOKEN,
                 http: httpx.Client | None = None):
        """Keep one HTTP client to the notebook; fail early when the notebook URL is missing."""
        if not base_url and http is None:
            raise OcrUnavailable("ASR_BASE_URL is not set: run notebooks/kaggle_ollama on Kaggle first")
        self._http = http or httpx.Client(base_url=base_url.rstrip("/"), timeout=DEFAULT_TIMEOUT_SECONDS,
                                          headers={"Authorization": f"Bearer {token}"})

    @classmethod
    def get_instance(cls) -> "VinternClient":
        """Return the shared client, creating it on first use (thread-safe)."""
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    def read_timetable(self, image_bytes: bytes) -> tuple[str, str]:
        """Upload the raw image and return (markdown, model name)."""
        start, host = time.perf_counter(), self._http.base_url.host
        try:
            response = self._http.post("/ocr", content=image_bytes,
                                       headers={"Content-Type": "application/octet-stream"})
            response.raise_for_status()
            body = response.json()
            markdown, model = body["text"].strip(), body.get("model", "vintern")
        except httpx.HTTPStatusError as error:
            logger.warning("OCR via %s failed: HTTP %d", host, error.response.status_code)
            # No URL in the message: it could reach the app and leak the tunnel address.
            error_type = OcrRejected if error.response.status_code == 400 else OcrUnavailable
            raise error_type(f"OCR server returned HTTP {error.response.status_code}") from error
        except (httpx.HTTPError, ValueError, KeyError, AttributeError) as error:
            logger.warning("OCR via %s unreachable: %s", host, error)
            raise OcrUnavailable("OCR server is unreachable") from error
        logger.info("OCR via %s ok in %.0fms", host, (time.perf_counter() - start) * 1000)
        return markdown, model
