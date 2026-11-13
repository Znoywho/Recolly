"""Voice endpoint (contract: docs/openapi.yaml, POST /voice/transcribe, R42 + R43).

audio → PhoWhisper transcript → VoiceTodoParser (Ollama words + rule deadline) → todo_draft.
The draft is not saved; the app shows it for confirmation and then calls the todo API.
"""

import os
import tempfile
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel

from app.core.deps import CurrentUser
from app.service.llm.ollama_client import OllamaError
from app.service.voice.time_parser import VIETNAM_TIMEZONE, VietnameseTimeParser
from app.service.voice.todo_parser import TodoDraft, VoiceTodoParser
from app.service.voice.transcriber import PhoWhisperTranscriber

MAX_AUDIO_BYTES = 25 * 1024 * 1024  # contract: max 25 MB

# Same values as app.models.enums.TodoCategory / Priority. Not imported from there: app.models has a
# circular import (todo.py <-> user.py) that breaks whenever app.models.enums is imported first.
TodoCategory = Literal["study", "assignment", "exam", "personal", "other"]
Priority = Literal["low", "medium", "high"]

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


def draft_from_rules_only(transcript: str, reference: datetime) -> TodoDraft:
    """Fallback when the LLM is down: the sentence itself as title, deadline from the rule parser."""
    deadline = VietnameseTimeParser().extract_deadline(transcript, reference)
    title = transcript.strip().rstrip(".").capitalize()
    return TodoDraft(title=title, category="other", priority="medium", deadline_at=deadline,
                     transcript=transcript, corrected_transcript=transcript, model="rules")


def to_response_draft(draft: TodoDraft) -> TodoDraftResponse:
    """Map the service dataclass onto the contract schema."""
    return TodoDraftResponse(title=draft.title, category=draft.category, priority=draft.priority,
                             deadline_at=draft.deadline_at)


@router.post("/transcribe", response_model=TranscribeResponse)
async def transcribe_audio(
    _user: CurrentUser,
    audio: UploadFile = File(...),
    reference_time: datetime | None = Form(default=None, description="Device 'now' for relative dates"),
) -> TranscribeResponse:
    """Save the upload to a temp file, transcribe it, then build a todo draft from the transcript."""
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio file")
    if len(audio_bytes) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Audio file too large (max 25 MB)")

    suffix = os.path.splitext(audio.filename or "")[1] or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as temp_audio:
        temp_audio.write(audio_bytes)
        temp_path = temp_audio.name

    try:
        transcriber = PhoWhisperTranscriber.get_instance()
        # Model inference blocks the CPU, so keep it off the event loop
        result = await run_in_threadpool(transcriber.transcribe_file, temp_path)
    except Exception as error:
        raise HTTPException(status_code=422, detail=f"Could not transcribe audio: {error}")
    finally:
        os.remove(temp_path)

    reference = reference_time or datetime.now(VIETNAM_TIMEZONE)
    try:
        draft = await run_in_threadpool(VoiceTodoParser().parse, result.text, reference)
        parser_name = "ollama"
    except OllamaError:
        draft = draft_from_rules_only(result.text, reference)
        parser_name = "rules"

    return TranscribeResponse(
        transcript=result.text,
        todo_draft=to_response_draft(draft) if result.text.strip() else None,
        parser=parser_name,
        corrected_transcript=draft.corrected_transcript if parser_name == "ollama" else None,
        model=f"{transcriber.model_name} + {draft.model}",
        processing_seconds=result.duration_seconds,
    )
