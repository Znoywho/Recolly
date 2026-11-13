"""Standalone demo: serve only the voice API (no PostgreSQL needed).

Run from server/:   python -m scripts.voice_demo
Then try:           curl -F "file=@sample.wav" http://localhost:8765/api/v1/voice/transcribe
"""

import uvicorn
from fastapi import FastAPI

from app.api.voice_api import router as voice_router
from app.service.voice.transcriber import PhoWhisperTranscriber


def create_demo_app() -> FastAPI:
    """Build a FastAPI app containing only the voice router."""
    demo_app = FastAPI(title="Recolly voice demo")
    demo_app.include_router(voice_router)
    return demo_app


if __name__ == "__main__":
    PhoWhisperTranscriber.get_instance()  # load the model before accepting requests
    uvicorn.run(create_demo_app(), host="0.0.0.0", port=8765)
