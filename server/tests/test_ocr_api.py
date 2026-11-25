"""OCR T1/T2 with Vintern (Kaggle) and Ollama replaced by fakes, plus the row → subject rules.

API tests need TEST_DATABASE_URL (jobs live in ocr_jobs); the parser tests do not.
"""

import os
from datetime import date, time, timedelta

import pytest
from sqlalchemy import update

from app.core.timeutil import now_utc
from app.models.ocr import OcrJob
from app.service.llm.ollama_client import OllamaClient, OllamaError
from app.service.ocr import ocr_jobs
from app.service.ocr.timetable_parser import FILLED_CONFIDENCE, PERIOD_TIMES, READ_CONFIDENCE, rows_to_subjects
from app.service.ocr.vintern_client import OcrRejected, OcrUnavailable, VinternClient
from tests.conftest import bearer, make_user

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 100
TODAY = date(2026, 11, 25)
ROW = {"name": "Giải tích 1", "code": "MA001", "room": "B4-01", "lecturer": None, "day_of_week": 2,
       "start_time": None, "end_time": None, "start_period": 1, "end_period": 3,
       "start_date": "2026-09-07", "end_date": "2026-12-20"}


class FakeVintern:
    """Stands in for the Kaggle OCR server: returns `markdown`, or raises `error`."""

    def __init__(self, markdown: str = "| Thứ | Môn |", error: Exception | None = None):
        self.markdown, self.error = markdown, error

    def read_timetable(self, image_bytes: bytes) -> tuple[str, str]:
        if self.error:
            raise self.error
        return self.markdown, "fake-vintern"


@pytest.fixture
def ocr(monkeypatch, tmp_path):
    """Photos go to tmp_path; `ocr.set(...)` decides what the fake Vintern and the fake LLM return."""
    monkeypatch.setattr(ocr_jobs, "IMAGE_DIR", tmp_path)
    state = {"vintern": FakeVintern(), "rows": [ROW], "llm_error": None}
    monkeypatch.setattr(VinternClient, "get_instance", classmethod(lambda cls: state["vintern"]))

    def fake_generate_json(self, system_prompt, user_message, json_schema, model_name=None):
        if state["llm_error"]:
            raise state["llm_error"]
        return {"subjects": state["rows"]}

    monkeypatch.setattr(OllamaClient, "generate_json", fake_generate_json)

    class Ocr:
        dir = tmp_path

        @staticmethod
        def set(vintern=None, rows=None, llm_error=None):
            state["vintern"] = vintern or FakeVintern()
            state["rows"] = [ROW] if rows is None else rows
            state["llm_error"] = llm_error

    return Ocr


def upload(client, auth, body=JPEG):
    return client.post("/api/v1/ocr/timetable", files={"image": ("tkb.jpg", body, "image/jpeg")}, headers=auth)


def poll(client, auth, job_id):
    return client.get(f"/api/v1/ocr/jobs/{job_id}", headers=auth)


# ─────────────────────────── T1 / T2 ───────────────────────────

def test_upload_then_poll_returns_subjects(client, auth, ocr):
    created = upload(client, auth)
    assert created.status_code == 202, created.text
    assert created.json()["status"] == "queued"
    job = poll(client, auth, created.json()["job_id"]).json()  # TestClient runs the background task first
    assert (job["status"], job["error"]) == ("succeeded", None)
    [subject] = job["result"]["subjects"]
    assert (subject["name"], subject["day_of_week"], subject["room"]) == ("Giải tích 1", 2, "B4-01")
    assert (subject["start_time"], subject["end_time"]) == (
        PERIOD_TIMES[1][0].strftime("%H:%M"), PERIOD_TIMES[3][1].strftime("%H:%M"))
    assert subject["confidence"] == READ_CONFIDENCE
    assert len(list(ocr.dir.iterdir())) == 1, "the photo stays on disk for 24 h (R12)"


@pytest.mark.parametrize("setup, code", [
    ({"vintern": FakeVintern(error=OcrUnavailable("down"))}, "OCR_MODEL_ERROR"),
    ({"llm_error": OllamaError("down")}, "OCR_MODEL_ERROR"),
    ({"vintern": FakeVintern(error=OcrRejected("bad"))}, "OCR_LOW_QUALITY"),
    ({"rows": []}, "OCR_NO_TABLE_FOUND"),
    ({"vintern": FakeVintern(error=RuntimeError("bug"))}, "OCR_MODEL_ERROR"),
])
def test_failed_jobs_carry_a_contract_code(client, auth, ocr, setup, code):
    ocr.set(**setup)
    job = poll(client, auth, upload(client, auth).json()["job_id"]).json()
    assert (job["status"], job["error"], job["result"]) == ("failed", code, None)


def test_upload_checks_the_file(client, auth, ocr):
    wrong = upload(client, auth, body=b"GIF89a not a timetable")
    assert (wrong.status_code, wrong.json()["code"]) == (400, "UNSUPPORTED_IMAGE")
    huge = upload(client, auth, body=JPEG + b"0" * (10 * 1024 * 1024))
    assert (huge.status_code, huge.json()["code"]) == (413, "FILE_TOO_LARGE")
    assert not list(ocr.dir.iterdir())


def test_upload_without_kaggle_is_503(client, auth, monkeypatch):
    with pytest.raises(OcrUnavailable):
        VinternClient(base_url="")  # what get_instance() raises while ASR_BASE_URL is empty
    monkeypatch.setattr(VinternClient, "get_instance",
                        classmethod(lambda cls: (_ for _ in ()).throw(OcrUnavailable("not set"))))
    response = upload(client, auth)
    assert (response.status_code, response.json()["code"]) == (503, "OCR_UNAVAILABLE")


def test_jobs_are_private_and_expire(client, auth, db, ocr):
    job_id = upload(client, auth).json()["job_id"]
    stranger = bearer(make_user(db, "other@example.com").id)
    assert poll(client, stranger, job_id).json()["code"] == "OCR_JOB_NOT_FOUND"

    old = now_utc() - timedelta(hours=25)
    db.execute(update(OcrJob).values(created_at=old))
    db.commit()
    for photo in ocr.dir.iterdir():
        os.utime(photo, (old.timestamp(), old.timestamp()))
    upload(client, auth)  # each upload cleans up jobs older than 24 h
    assert poll(client, auth, job_id).json()["code"] == "OCR_JOB_NOT_FOUND"
    assert len(list(ocr.dir.iterdir())) == 1


def test_a_job_stuck_after_a_restart_fails(client, auth, db, ocr):
    job_id = upload(client, auth).json()["job_id"]
    db.execute(update(OcrJob).values(status="processing", error_code=None, result=None,
                                     created_at=now_utc() - timedelta(minutes=11)))
    db.commit()
    job = poll(client, auth, job_id).json()
    assert (job["status"], job["error"]) == ("failed", "OCR_MODEL_ERROR")


# ─────────────────────────── row → subject ───────────────────────────

def test_rows_use_clock_times_when_the_table_has_them():
    [subject] = rows_to_subjects([{**ROW, "start_time": "7h30", "end_time": "9:30"}], TODAY)
    assert (subject.start_time, subject.end_time) == (time(7, 30), time(9, 30))


def test_missing_dates_are_filled_and_flagged():
    [subject] = rows_to_subjects([{**ROW, "start_date": None, "end_date": "not a date"}], TODAY)
    assert (subject.start_date, subject.end_date) == (TODAY, TODAY + timedelta(weeks=15))
    assert subject.confidence == FILLED_CONFIDENCE


def test_broken_rows_are_dropped():
    rows = [
        {**ROW, "start_period": 99},                              # unknown period
        {**ROW, "start_period": None, "end_period": None},        # no time at all
        {**ROW, "day_of_week": 8},                                # not a weekday
        {**ROW, "name": "  "},                                    # no name
        {**ROW, "start_time": "10:00", "end_time": "08:00"},      # ends before it starts
        "not a row",
        ROW,
    ]
    assert [s.name for s in rows_to_subjects(rows, TODAY)] == ["Giải tích 1"]


# ─────────────────────────── Kaggle client ───────────────────────────

def vintern_answering(status: int, body: dict | None = None) -> VinternClient:
    """A real VinternClient whose HTTP calls return `status` and `body`."""
    import httpx

    def handler(request):
        assert request.headers["Authorization"] == "Bearer secret"
        return httpx.Response(status, json=body or {})

    http = httpx.Client(base_url="http://kaggle", transport=httpx.MockTransport(handler),
                        headers={"Authorization": "Bearer secret"})
    return VinternClient(http=http)


def test_vintern_client_maps_http_answers():
    assert vintern_answering(200, {"text": " | a | \n", "model": "v"}).read_timetable(JPEG) == ("| a |", "v")
    with pytest.raises(OcrRejected):
        vintern_answering(400).read_timetable(JPEG)
    with pytest.raises(OcrUnavailable):
        vintern_answering(502).read_timetable(JPEG)
    with pytest.raises(OcrUnavailable):
        vintern_answering(200, {"no_text": 1}).read_timetable(JPEG)
