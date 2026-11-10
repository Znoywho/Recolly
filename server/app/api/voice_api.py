"""Voice endpoints: upload a recording from the phone, get Vietnamese text back."""

import os
import tempfile

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel

from app.service.voice.transcriber import PhoWhisperTranscriber

MAX_AUDIO_BYTES = 10 * 1024 * 1024  # 10 MB is roughly 10 minutes of m4a

router = APIRouter(prefix="/api/v1/voice", tags=["voice"])


class TranscribeResponse(BaseModel):
    """Response body for POST /api/v1/voice/transcribe."""

    transcript: str
    model: str
    processing_seconds: float


@router.post("/transcribe", response_model=TranscribeResponse)
async def transcribe_audio(file: UploadFile) -> TranscribeResponse:
    """Save the uploaded audio to a temp file and run PhoWhisper on it."""
    audio_bytes = await file.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio file")
    if len(audio_bytes) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Audio file too large (max 10 MB)")

    suffix = os.path.splitext(file.filename or "")[1] or ".wav"
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

    return TranscribeResponse(
        transcript=result.text,
        model=transcriber.model_name,
        processing_seconds=result.duration_seconds,
    )
