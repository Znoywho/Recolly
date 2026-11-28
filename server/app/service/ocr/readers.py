"""Which model reads timetable photos: OCR_PROVIDER=gemini (default) or vintern.

A reader works in two steps, so the raw model output can be saved before it is parsed:
    raw = reader.read_raw(image_bytes, suffix)
    subjects = reader.parse(raw, today)
"""

import logging
from datetime import date

from app.schemas.timetable import OcrSubject
from app.service.llm.gemini_client import GeminiClient, GeminiRejected
from app.service.llm.providers import provider_from_env
from app.service.ocr.gemini_reader import GeminiReader
from app.service.ocr.timetable_parser import TimetableParser
from app.service.ocr.vintern_client import OcrUnavailable, VinternClient

OCR_PROVIDER = provider_from_env("OCR_PROVIDER", ("gemini", "vintern"))

logger = logging.getLogger(__name__)
if OCR_PROVIDER == "gemini":
    logger.warning("OCR_PROVIDER=gemini: photos are sent to Google; use test data only on the unpaid tier")


class VinternReader:
    """Vintern (Kaggle) reads the photo as markdown, then the Ollama parser turns it into subjects."""

    def read_raw(self, image_bytes: bytes, suffix: str) -> str:
        """The timetable as markdown (Vintern detects the image format itself)."""
        markdown, _ = VinternClient.get_instance().read_timetable(image_bytes)
        return markdown

    def parse(self, raw: str, today: date) -> list[OcrSubject]:
        """Subjects found in the markdown."""
        return TimetableParser().parse(raw, today)


def build_reader() -> VinternReader | GeminiReader:
    """The reader for OCR_PROVIDER."""
    if OCR_PROVIDER == "gemini":
        # A background job: a few short retries ride out the per-minute rate limit.
        return GeminiReader(GeminiClient(attempts=3, wait_seconds=10))
    return VinternReader()


def check_ocr_available() -> None:
    """Raise OcrUnavailable when the chosen provider is not configured."""
    if OCR_PROVIDER == "gemini":
        try:
            GeminiClient()
        except GeminiRejected as error:
            raise OcrUnavailable(str(error)) from error
    else:
        VinternClient.get_instance()
