"""Vietnamese speech-to-text using VinAI's PhoWhisper (Hugging Face transformers)."""

import os
import time
from dataclasses import dataclass
from threading import Lock

from transformers import pipeline

DEFAULT_MODEL_NAME = os.getenv("PHOWHISPER_MODEL", "vinai/PhoWhisper-small")


@dataclass
class TranscriptionResult:
    """Text recognized from one audio file, plus how long recognition took."""

    text: str
    duration_seconds: float


class PhoWhisperTranscriber:
    """Loads PhoWhisper once and turns audio files into Vietnamese text."""

    _instance: "PhoWhisperTranscriber | None" = None
    _instance_lock = Lock()

    def __init__(self, model_name: str = DEFAULT_MODEL_NAME):
        """Load the ASR pipeline on CPU (slow: a few seconds, do it only once)."""
        self.model_name = model_name
        self._pipeline = pipeline(
            "automatic-speech-recognition",
            model=model_name,
            device="cpu",
            chunk_length_s=30,  # split long recordings into 30s windows
        )

    @classmethod
    def get_instance(cls) -> "PhoWhisperTranscriber":
        """Return the shared transcriber, creating it on first use (thread-safe)."""
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    def transcribe_file(self, audio_path: str) -> TranscriptionResult:
        """Decode the audio file with ffmpeg and return the recognized text."""
        start = time.perf_counter()
        output = self._pipeline(audio_path)
        elapsed = time.perf_counter() - start
        return TranscriptionResult(text=output["text"].strip(), duration_seconds=round(elapsed, 2))
