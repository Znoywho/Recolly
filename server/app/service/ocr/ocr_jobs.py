"""OCR jobs (R09–R11): save the photo, then read it in a background task (OCR_PROVIDER: Vintern + Ollama, or Gemini).

    POST /ocr/timetable ──► create_job (file + row, committed) ──► 202 ──► process_job (background)
                                                                          ├─ subjects → succeeded
                                                                          ├─ no rows → failed OCR_NO_TABLE_FOUND
                                                                          ├─ bad image → failed OCR_LOW_QUALITY
                                                                          └─ model unreachable → failed OCR_MODEL_ERROR
    GET /ocr/jobs/{id} ◄── the app polls every ~2 s

No retry queue (unlike voice): the user is waiting on the scan screen and can simply scan again.
"""

import logging
import os
import tempfile
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.core.timeutil import today
from app.db.session import SessionLocal
from app.models.enums import JobStatus
from app.models.ocr import OcrJob
from app.models.user import User
from app.service.llm.gemini_client import GeminiBadReply, GeminiError
from app.service.llm.ollama_client import OllamaError
from app.service.ocr.readers import build_reader
from app.service.ocr.vintern_client import OcrRejected, OcrUnavailable
from app.service.voice.voice_jobs import is_job_audio

# Only the server process reads the photo, so the container's temp folder is enough (no volume).
IMAGE_DIR = Path(os.getenv("OCR_IMAGE_DIR", str(Path(tempfile.gettempdir()) / "recolly-ocr")))
KEEP_FOR = timedelta(hours=24)  # contract: jobs are kept for 24 h, then T2 returns 404

logger = logging.getLogger(__name__)


def create_job(db: Session, user: User, image_bytes: bytes, suffix: str) -> OcrJob:
    """Write the photo and its row, committed before the background task opens its own session."""
    job = OcrJob(id=uuid.uuid4(), user_id=user.id, status=JobStatus.QUEUED)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    image_path = IMAGE_DIR / f"{job.id}{suffix}"
    image_path.write_bytes(image_bytes)
    job.image_path = str(image_path)
    db.add(job)
    db.commit()
    return job


def process_job(job_id: uuid.UUID) -> None:
    """Run OCR + parsing for one job; always ends succeeded or failed (runs after the 202 is sent)."""
    with SessionLocal() as db:
        job = db.get(OcrJob, job_id)
        job.status = JobStatus.PROCESSING
        db.commit()  # end the transaction: no pooled DB connection is held during the Kaggle/LLM calls
        user_today = today(ZoneInfo(db.get(User, job.user_id).timezone))
        try:
            reader, image_path = build_reader(), Path(job.image_path)
            job.raw_output = reader.read_raw(image_path.read_bytes(), image_path.suffix)  # kept for the check (R12)
            subjects = reader.parse(job.raw_output, user_today)
        except (OcrRejected, GeminiBadReply):
            job.status, job.error_code = JobStatus.FAILED, "OCR_LOW_QUALITY"
        except (OcrUnavailable, OllamaError, GeminiError):
            job.status, job.error_code = JobStatus.FAILED, "OCR_MODEL_ERROR"
        except Exception:  # a background task has no caller: never leave the app polling a stuck job
            logger.exception("OCR job %s crashed", job.id)
            job.status, job.error_code = JobStatus.FAILED, "OCR_MODEL_ERROR"
        else:
            if subjects:
                job.status = JobStatus.SUCCEEDED
                job.result = {"subjects": [subject.model_dump(mode="json") for subject in subjects]}
            else:
                job.status, job.error_code = JobStatus.FAILED, "OCR_NO_TABLE_FOUND"
        db.commit()
        # Counts only: the timetable is the user's private content.
        logger.info("OCR job=%s user=%s status=%s error=%s subjects=%d", job.id, job.user_id, job.status,
                    job.error_code, len((job.result or {}).get("subjects", [])))


def delete_expired(db: Session, now: datetime) -> int:
    """Delete jobs older than KEEP_FOR and every photo older than that (also orphans of deleted users)."""
    cutoff = now - KEEP_FOR
    deleted = db.execute(delete(OcrJob).where(OcrJob.created_at < cutoff)).rowcount
    db.commit()
    if IMAGE_DIR.exists():
        for image_path in IMAGE_DIR.iterdir():
            if is_job_audio(image_path) and image_path.is_file() and image_path.stat().st_mtime < cutoff.timestamp():
                image_path.unlink(missing_ok=True)
    return deleted
