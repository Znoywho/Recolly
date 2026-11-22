"""Voice V1/V2 + the retry worker, with the Kaggle speech server and the LLM replaced by fakes.

Needs TEST_DATABASE_URL (recordings are saved in voice_jobs before speech-to-text).
"""

import os
import time
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import update

from app.core.timeutil import now_utc
from app.models.enums import JobStatus
from app.models.notification import Device
from app.models.voice import VoiceJob
from app.service.llm.ollama_client import OllamaError
from app.service.voice import voice_jobs
from app.service.voice.todo_parser import TodoDraft, VoiceTodoParser
from app.service.voice.transcriber import AsrRejected, AsrUnavailable, PhoWhisperTranscriber, TranscriptionResult
from tests.conftest import bearer, make_user

REFERENCE = "2026-11-10T14:00:00+07:00"  # a Tuesday


class FakeTranscriber:
    """Stands in for the Kaggle speech server: hears `text`, or raises `error` (server down / bad audio)."""

    model_name = "fake-whisper"

    def __init__(self, text: str = "", error: Exception | None = None):
        self.text, self.error = text, error

    def transcribe_file(self, path: str) -> TranscriptionResult:
        assert os.path.exists(path), "the recording must be on disk before Kaggle is called"
        if self.error:
            raise self.error
        return TranscriptionResult(text=self.text, duration_seconds=0.01)


class FakeSender:
    """Records pushes instead of calling FCM."""

    def __init__(self):
        self.sent = []

    def send(self, fcm_token, payload):
        self.sent.append((fcm_token, payload))
        return True


@pytest.fixture
def speech(monkeypatch, tmp_path):
    """Audio files go to tmp_path; `speech.set(...)` decides what the fake speech server does."""
    monkeypatch.setattr(voice_jobs, "AUDIO_DIR", tmp_path)
    holder = {"t": FakeTranscriber("x")}
    monkeypatch.setattr(PhoWhisperTranscriber, "get_instance", classmethod(lambda cls: holder["t"]))
    monkeypatch.setattr(VoiceTodoParser, "parse",
                        lambda self, t, r: (_ for _ in ()).throw(OllamaError("down")))  # rules unless a test overrides

    class Speech:
        dir = tmp_path

        @staticmethod
        def set(text: str = "", error: Exception | None = None):
            holder["t"] = FakeTranscriber(text, error)

    return Speech


def post_audio(client, auth, filename="clip.m4a", body=b"fake-bytes", **form):
    return client.post("/api/v1/voice/transcribe", files={"audio": (filename, body, "audio/mp4")},
                       data=form, headers=auth)


def run_worker(now=None, sender=None):
    from app.jobs.process_voice import run_process_voice

    return run_process_voice(now=now, sender=sender or FakeSender())


# ───────────── Kaggle up: 200 as before, recording saved ─────────────

def test_ollama_draft_with_rule_deadline(client, auth, db, speech, monkeypatch):
    speech.set("chiều mai bush scott lên kết thúc trước năm giờ")

    def fake_parse(self, transcript, reference):
        corrected = "chiều mai push code lên GitHub trước năm giờ"
        return TodoDraft(title="Push code lên GitHub", category="assignment", priority="medium",
                         deadline_at=self.time_parser.extract_deadline(corrected, reference),
                         transcript=transcript, corrected_transcript=corrected, model="qwen2.5:14b")
    monkeypatch.setattr(VoiceTodoParser, "parse", fake_parse)

    response = post_audio(client, auth, reference_time=REFERENCE)

    assert response.status_code == 200
    body = response.json()
    assert body["parser"] == "ollama"
    assert body["todo_draft"]["title"] == "Push code lên GitHub"
    assert body["todo_draft"]["category"] == "assignment"
    assert body["todo_draft"]["deadline_at"] == "2026-11-11T17:00:00+07:00"
    assert body["corrected_transcript"].endswith("GitHub trước năm giờ")
    assert body["model"] == "fake-whisper + qwen2.5:14b"
    job = db.get(VoiceJob, body["job_id"])
    assert job.status == JobStatus.SUCCEEDED and job.attempts == 1 and os.path.exists(job.audio_path)


def test_falls_back_to_rules_when_ollama_is_down(client, auth, speech):
    speech.set("tối thứ sáu này tám giờ ôn thi với bạn")

    body = post_audio(client, auth, reference_time=REFERENCE).json()

    assert body["parser"] == "rules"
    assert body["todo_draft"]["deadline_at"] == "2026-11-13T20:00:00+07:00"
    assert body["todo_draft"]["category"] == "other"
    assert body["corrected_transcript"] is None


def test_reference_time_without_offset_is_the_users_clock(client, auth, speech):
    speech.set("tối mai tám giờ ôn thi")
    # 20:00 in Hà Nội; read as UTC it would be 03:00 on the 11th and "tối mai" would land on the 12th
    body = post_audio(client, auth, reference_time="2026-11-10T20:00:00").json()
    assert body["todo_draft"]["deadline_at"] == "2026-11-11T20:00:00+07:00"


def test_rules_fallback_uses_server_time_when_no_reference_time(client, auth, speech):
    speech.set("mua sách giáo trình")
    body = post_audio(client, auth).json()
    assert body["todo_draft"]["deadline_at"] is None and body["todo_draft"]["title"] == "Mua sách giáo trình"


def test_requires_login(client, speech):
    assert post_audio(client, {}).status_code == 401


def test_rejects_empty_upload(client, auth, speech):
    assert post_audio(client, auth, body=b"").status_code == 400


def test_client_filename_cannot_choose_the_path(client, auth, db, speech):
    body = post_audio(client, auth, filename="../../evil.sh").json()
    job = db.get(VoiceJob, body["job_id"])
    assert os.path.dirname(job.audio_path) == str(speech.dir) and job.audio_path.endswith(".audio")


def test_undecodable_audio_fails_at_once(client, auth, db, speech):
    speech.set(error=AsrRejected("speech server returned HTTP 400"))

    assert post_audio(client, auth).status_code == 422
    [job] = db.query(VoiceJob).all()
    assert job.status == JobStatus.FAILED and job.error_code == "VOICE_BAD_AUDIO"


# ───────────── Kaggle down: 202, saved, retried by the worker ─────────────

def test_kaggle_down_saves_the_recording_and_the_worker_finishes_it(client, auth, user, db, speech):
    speech.set(error=AsrUnavailable("speech server is unreachable"))
    response = post_audio(client, auth, reference_time=REFERENCE)

    assert response.status_code == 202
    job_id = response.json()["job_id"]
    assert response.json()["status"] == "queued"
    polled = client.get(f"/api/v1/voice/jobs/{job_id}", headers=auth).json()
    assert polled["status"] == "queued" and polled["result"] is None

    assert run_worker()["queued"] == 1  # still down: stays queued

    db.add(Device(user_id=user.id, fcm_token="phone-token"))
    db.commit()
    speech.set("tối thứ sáu này tám giờ ôn thi với bạn")  # Kaggle is back, hours later
    sender = FakeSender()
    assert run_worker(sender=sender)["succeeded"] == 1

    polled = client.get(f"/api/v1/voice/jobs/{job_id}", headers=auth).json()
    assert polled["status"] == "succeeded" and polled["error"] is None
    # "thứ sáu này" still counts from the recording day, not from the retry
    assert polled["result"]["todo_draft"]["deadline_at"] == "2026-11-13T20:00:00+07:00"
    assert polled["result"]["job_id"] == job_id
    [(token, payload)] = sender.sent
    assert token == "phone-token" and payload["type"] == "voice_ready" and payload["job_id"] == job_id


def test_worker_gives_up_after_a_day(client, auth, db, speech):
    speech.set(error=AsrUnavailable("down"))
    job_id = post_audio(client, auth).json()["job_id"]

    assert run_worker(now=now_utc() + timedelta(hours=25))["gave_up"] == 1

    polled = client.get(f"/api/v1/voice/jobs/{job_id}", headers=auth).json()
    assert polled["status"] == "failed" and polled["error"] == "VOICE_ASR_UNAVAILABLE"


def test_worker_retries_a_job_whose_process_died(client, auth, db, speech):
    speech.set(error=AsrUnavailable("down"))
    job_id = post_audio(client, auth).json()["job_id"]
    db.execute(update(VoiceJob).values(status=JobStatus.PROCESSING))  # as if the API crashed mid-call
    db.commit()
    speech.set("học bài")

    assert run_worker()["succeeded"] == 0  # fresh "processing": someone may still be on it
    assert run_worker(now=now_utc() + timedelta(minutes=11))["succeeded"] == 1
    assert client.get(f"/api/v1/voice/jobs/{job_id}", headers=auth).json()["status"] == "succeeded"


def test_week_old_recordings_are_deleted(client, auth, db, speech):
    speech.set("học bài")
    job_id = post_audio(client, auth).json()["job_id"]
    audio_path = db.get(VoiceJob, job_id).audio_path
    eight_days_ago = time.time() - 8 * 86400
    os.utime(audio_path, (eight_days_ago, eight_days_ago))
    orphan = speech.dir / f"{uuid.uuid4()}.m4a"  # recording of a user who deleted the account
    not_ours = speech.dir / "thesis.pdf"  # VOICE_AUDIO_DIR pointed at a folder with other files
    for path in (orphan, not_ours):
        path.write_bytes(b"x")
        os.utime(path, (eight_days_ago, eight_days_ago))

    assert run_worker(now=now_utc() + timedelta(days=8))["deleted"] == 1

    assert not os.path.exists(audio_path) and not orphan.exists()
    assert not_ours.exists()
    assert client.get(f"/api/v1/voice/jobs/{job_id}", headers=auth).status_code == 404


def test_cannot_read_another_users_job(client, auth, db, speech):
    speech.set("học bài")
    job_id = post_audio(client, auth).json()["job_id"]
    stranger = make_user(db, email="other@example.com")

    response = client.get(f"/api/v1/voice/jobs/{job_id}", headers=bearer(stranger.id))

    assert response.status_code == 404 and response.json()["code"] == "VOICE_JOB_NOT_FOUND"
