"""POST /api/v1/voice/transcribe with the ASR and the LLM replaced by fakes (no models, no network)."""

from datetime import datetime

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import voice_api
from app.service.llm.ollama_client import OllamaError
from app.service.voice.time_parser import VIETNAM_TIMEZONE
from app.service.voice.todo_parser import TodoDraft
from app.service.voice.transcriber import TranscriptionResult

REFERENCE = "2026-11-10T14:00:00+07:00"  # a Tuesday


class FakeTranscriber:
    """Stands in for PhoWhisperTranscriber: always hears the same sentence."""

    model_name = "fake-whisper"

    def __init__(self, text: str):
        self.text = text

    def transcribe_file(self, _path: str) -> TranscriptionResult:
        return TranscriptionResult(text=self.text, duration_seconds=0.01)


@pytest.fixture
def client(monkeypatch):
    """Test app with only the voice router; the transcriber is faked per test via `set_transcript`."""
    app = FastAPI()
    app.include_router(voice_api.router)
    holder = {}
    monkeypatch.setattr(voice_api.PhoWhisperTranscriber, "get_instance", classmethod(lambda cls: holder["t"]))
    test_client = TestClient(app)
    test_client.set_transcript = lambda text: holder.__setitem__("t", FakeTranscriber(text))
    return test_client


def post_audio(client, **form):
    return client.post("/api/v1/voice/transcribe", files={"audio": ("clip.m4a", b"fake-bytes", "audio/mp4")}, data=form)


def test_ollama_draft_with_rule_deadline(client, monkeypatch):
    client.set_transcript("chiều mai bush scott lên kết thúc trước năm giờ")

    def fake_parse(self, transcript, reference):
        corrected = "chiều mai push code lên GitHub trước năm giờ"
        return TodoDraft(title="Push code lên GitHub", category="assignment", priority="medium",
                         deadline_at=self.time_parser.extract_deadline(corrected, reference),
                         transcript=transcript, corrected_transcript=corrected, model="qwen2.5:14b")
    monkeypatch.setattr(voice_api.VoiceTodoParser, "parse", fake_parse)

    body = post_audio(client, reference_time=REFERENCE).json()

    assert body["parser"] == "ollama"
    assert body["todo_draft"]["title"] == "Push code lên GitHub"
    assert body["todo_draft"]["category"] == "assignment"
    assert body["todo_draft"]["deadline_at"] == "2026-11-11T17:00:00+07:00"
    assert body["corrected_transcript"].endswith("GitHub trước năm giờ")
    assert body["model"] == "fake-whisper + qwen2.5:14b"


def test_falls_back_to_rules_when_ollama_is_down(client, monkeypatch):
    client.set_transcript("tối thứ sáu này tám giờ ôn thi với bạn")
    monkeypatch.setattr(voice_api.VoiceTodoParser, "parse", lambda self, t, r: (_ for _ in ()).throw(OllamaError("down")))

    body = post_audio(client, reference_time=REFERENCE).json()

    assert body["parser"] == "rules"
    assert body["todo_draft"]["deadline_at"] == "2026-11-13T20:00:00+07:00"
    assert body["todo_draft"]["category"] == "other"
    assert body["corrected_transcript"] is None


def test_rejects_empty_upload(client):
    client.set_transcript("x")
    response = client.post("/api/v1/voice/transcribe", files={"audio": ("clip.m4a", b"", "audio/mp4")})
    assert response.status_code == 400


def test_rules_fallback_uses_server_time_when_no_reference_time(client, monkeypatch):
    client.set_transcript("mua sách giáo trình")
    monkeypatch.setattr(voice_api.VoiceTodoParser, "parse", lambda self, t, r: (_ for _ in ()).throw(OllamaError("down")))
    body = post_audio(client).json()
    assert body["todo_draft"]["deadline_at"] is None and body["todo_draft"]["title"] == "Mua sách giáo trình"
