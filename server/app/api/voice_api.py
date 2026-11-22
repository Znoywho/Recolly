"""Voice endpoints (contract: docs/openapi.yaml, V1 POST /voice/transcribe, V2 GET /voice/jobs/{id}; R42 + R43).

The recording is saved first (voice_jobs + audio file), then sent to PhoWhisper on Kaggle:
Kaggle up → 200 with the draft; Kaggle down → 202, app.jobs.process_voice retries and pushes "voice_ready".
The draft is not saved as a todo; the app shows it for confirmation and then calls the todo API.
"""

import os
import uuid
from datetime import datetime

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.core.deps import CurrentUser, DbSession, user_tz
from app.core.errors import not_found
from app.core.timeutil import now_utc
from app.models.enums import JobStatus, Priority, TodoCategory
from app.models.voice import VoiceJob
from app.service.voice.voice_jobs import create_job, process_job

MAX_AUDIO_BYTES = 25 * 1024 * 1024  # contract: max 25 MB
# The filename comes from the client: only these extensions reach the disk.
AUDIO_SUFFIXES = {".m4a", ".mp4", ".aac", ".wav", ".ogg", ".mp3"}

router = APIRouter(prefix="/voice", tags=["Voice"])  # mounted under /api/v1 by app.api.api_router


class TodoDraftResponse(BaseModel):
    """`TodoDraft` in the OpenAPI contract: the todo fields the user confirms before saving."""

    title: str
    description: str | None = None
    category: TodoCategory
    priority: Priority
    deadline_at: datetime | None
    estimated_minutes: int | None = None
    difficulty: int | None = None


class TranscribeResponse(BaseModel):
    """`TranscribeResponse` in the contract, plus diagnostics (model, timing, repaired transcript)."""

    transcript: str
    todo_draft: TodoDraftResponse | None
    parser: str                      # "ollama" | "rules"  (rules = Ollama unreachable, deadline-only fallback)
    corrected_transcript: str | None = None
    model: str
    processing_seconds: float
    job_id: uuid.UUID | None = None  # the saved recording, for GET /voice/jobs/{job_id}


class VoiceJobCreated(BaseModel):
    """202 body: the recording is saved and will be transcribed when the speech server is back."""

    job_id: uuid.UUID
    status: JobStatus


class VoiceJobRead(BaseModel):
    """`VoiceJob` in the contract (same shape as OcrJob)."""

    job_id: uuid.UUID
    status: JobStatus
    error: str | None            # VOICE_ASR_UNAVAILABLE | VOICE_BAD_AUDIO
    result: TranscribeResponse | None
    created_at: datetime


def job_result(job: VoiceJob) -> TranscribeResponse | None:
    """The stored draft of a succeeded job, with its id."""
    return TranscribeResponse(**job.result, job_id=job.id) if job.result else None


@router.post("/transcribe", response_model=TranscribeResponse,
             responses={202: {"model": VoiceJobCreated, "description": "Saved; speech server down, retried later"}})
async def transcribe_audio(
    user: CurrentUser,
    db: DbSession,
    audio: UploadFile = File(...),
    reference_time: datetime | None = Form(default=None, description="Device 'now' for relative dates"),
):
    """Save the recording, then try Kaggle now: 200 with the draft, or 202 when it must wait in the queue."""
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio file")
    if len(audio_bytes) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Audio file too large (max 25 MB)")

    if reference_time is not None and reference_time.tzinfo is None:
        # No offset (e.g. typed in Swagger): it is the user's wall clock, not UTC.
        reference_time = reference_time.replace(tzinfo=user_tz(user))
    suffix = os.path.splitext(audio.filename or "")[1].lower()
    job = create_job(db, user, audio_bytes, suffix if suffix in AUDIO_SUFFIXES else ".audio",
                     reference_time or now_utc())
    # Network calls (Kaggle ASR + LLM) block, so keep them off the event loop
    await run_in_threadpool(process_job, db, job)

    if job.status == JobStatus.SUCCEEDED:
        return job_result(job)
    if job.status == JobStatus.FAILED:
        raise HTTPException(status_code=422, detail="Could not transcribe audio: the file cannot be decoded")
    return JSONResponse(VoiceJobCreated(job_id=job.id, status=job.status).model_dump(mode="json"), status_code=202)


@router.get("/jobs/{job_id}", response_model=VoiceJobRead)
def get_voice_job(job_id: uuid.UUID, user: CurrentUser, db: DbSession) -> VoiceJobRead:
    """V2 · State of a saved recording; poll it after a 202. Jobs are deleted after 7 days."""
    job = db.get(VoiceJob, job_id)
    if job is None or job.user_id != user.id:
        raise not_found("voice_job")
    return VoiceJobRead(job_id=job.id, status=job.status, error=job.error_code, result=job_result(job),
                        created_at=job.created_at)
