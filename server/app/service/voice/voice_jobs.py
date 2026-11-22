"""Voice jobs: save the recording first, then speech-to-text on Kaggle (now, or later by the worker).

    POST /voice/transcribe ──► create_job (file + row, committed) ──► process_job
                                                                       ├─ succeeded → 200 + draft
                                                                       ├─ bad audio → failed (422)
                                                                       └─ Kaggle down → queued (202)
    app.jobs.process_voice (every minute) ──► process_job on queued jobs ──► push "voice_ready"
"""

import logging
import os
import tempfile
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.models.enums import JobStatus
from app.models.user import User
from app.models.voice import VoiceJob
from app.service.llm.ollama_client import OllamaError
from app.service.voice.time_parser import VietnameseTimeParser
from app.service.voice.todo_parser import TodoDraft, VoiceTodoParser
from app.service.voice.transcriber import AsrRejected, AsrUnavailable, PhoWhisperTranscriber

# Docker: the `voice-audio` volume. Local venv: the system temp folder.
AUDIO_DIR = Path(os.getenv("VOICE_AUDIO_DIR", str(Path(tempfile.gettempdir()) / "recolly-voice")))
KEEP_FOR = timedelta(days=7)  # recordings and jobs are personal data: delete after a week

logger = logging.getLogger(__name__)


def create_job(db: Session, user: User, audio_bytes: bytes, suffix: str, reference: datetime) -> VoiceJob:
    """Write the audio file and its row, committed before any Kaggle call so nothing is lost."""
    job = VoiceJob(id=uuid.uuid4(), user_id=user.id, status=JobStatus.PROCESSING, reference_time=reference)
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    audio_path = AUDIO_DIR / f"{job.id}{suffix}"
    audio_path.write_bytes(audio_bytes)
    job.audio_path = str(audio_path)
    db.add(job)
    db.commit()
    return job


def draft_from_rules_only(transcript: str, reference: datetime) -> TodoDraft:
    """Fallback when the LLM is down: the sentence itself as title, deadline from the rule parser."""
    deadline = VietnameseTimeParser().extract_deadline(transcript, reference)
    title = transcript.strip().rstrip(".").capitalize()
    return TodoDraft(title=title, category="other", priority="medium", deadline_at=deadline,
                     transcript=transcript, corrected_transcript=transcript, model="rules")


def build_result(transcript: str, draft: TodoDraft, parser_name: str, asr_model: str,
                 seconds: float) -> dict[str, Any]:
    """The TranscribeResponse body as JSON-ready data (stored in voice_jobs.result)."""
    todo_draft = None
    if transcript.strip():
        todo_draft = {"title": draft.title, "category": draft.category, "priority": draft.priority,
                      "deadline_at": draft.deadline_at.isoformat() if draft.deadline_at else None}
    return {"transcript": transcript, "todo_draft": todo_draft, "parser": parser_name,
            "corrected_transcript": draft.corrected_transcript if parser_name == "ollama" else None,
            "model": f"{asr_model} + {draft.model}", "processing_seconds": seconds}


def process_job(db: Session, job: VoiceJob) -> None:
    """Transcribe on Kaggle and draft a todo; ends succeeded, failed, or queued again when Kaggle is down."""
    audio_path = job.audio_path
    job.attempts += 1
    db.commit()  # end the transaction: no pooled DB connection is held during the Kaggle/LLM calls
    started = time.perf_counter()
    try:
        transcriber = PhoWhisperTranscriber.get_instance()
        heard = transcriber.transcribe_file(audio_path)
    except AsrRejected:
        job.status, job.error_code = JobStatus.FAILED, "VOICE_BAD_AUDIO"
        db.commit()
        return
    except AsrUnavailable:
        job.status = JobStatus.QUEUED
        db.commit()
        logger.info("Voice job %s queued: speech server down (attempt %d)", job.id, job.attempts)
        return

    # Postgres returns UTC; relative dates ("tối mai") must be read in the user's own timezone.
    reference = job.reference_time.astimezone(ZoneInfo(db.get(User, job.user_id).timezone))
    try:
        draft, parser_name = VoiceTodoParser().parse(heard.text, reference), "ollama"
    except OllamaError:
        draft, parser_name = draft_from_rules_only(heard.text, reference), "rules"
    job.result = build_result(heard.text, draft, parser_name, transcriber.model_name,
                              round(time.perf_counter() - started, 2))
    job.status = JobStatus.SUCCEEDED
    db.commit()
    # Length only: the transcript is the user's private content.
    logger.info("Transcribed job=%s user=%s chars=%d parser=%s attempt=%d", job.id, job.user_id,
                len(heard.text), parser_name, job.attempts)


def is_job_audio(path: Path) -> bool:
    """True only for files named `<job uuid>.<ext>`: a misconfigured VOICE_AUDIO_DIR must not lose other files."""
    try:
        uuid.UUID(path.stem)
        return True
    except ValueError:
        return False


def delete_expired(db: Session, now: datetime) -> int:
    """Delete jobs older than KEEP_FOR and every audio file older than that (also orphans of deleted users)."""
    cutoff = now - KEEP_FOR
    deleted = db.execute(delete(VoiceJob).where(VoiceJob.created_at < cutoff)).rowcount
    db.commit()
    if AUDIO_DIR.exists():
        for audio_path in AUDIO_DIR.iterdir():
            if (is_job_audio(audio_path) and audio_path.is_file()
                    and audio_path.stat().st_mtime < cutoff.timestamp()):
                audio_path.unlink(missing_ok=True)
    return deleted
