"""The Gemini evaluation script, with the API replaced by an httpx mock."""

import json
from datetime import date

import httpx
import pytest

from app.service.llm.gemini_client import GeminiClient, GeminiRejected
from app.service.llm.guard import UNTRUSTED_DATA_RULE
from app.service.ocr.gemini_reader import DAY_NAMES, IMAGE_PROMPT, GeminiReader, number_days
from scripts.gemini_ocr_eval import finished_files, is_synthetic, run, total_tokens
from scripts.ocr_eval import CANARY, Photo, injection_success_rate, load_photos

TODAY = date(2026, 11, 27)
ROW = {"name": "Giải tích", "code": None, "room": "B201", "lecturer": None, "day": "Thứ 3",
       "start_time": "07:00", "end_time": "09:50", "start_period": None, "end_period": None,
       "start_date": None, "end_date": None}


def completed(text: str) -> httpx.Response:
    usage = {"total_input_tokens": 900, "total_output_tokens": 100, "total_tokens": 1000}
    return httpx.Response(200, json={"status": "completed", "usage": usage, "steps": [
        {"type": "thought", "content": [{"type": "text", "text": "ignored"}]},
        {"type": "model_output", "content": [{"type": "text", "text": text}]}]})


def reader_answering(*responses: httpx.Response) -> tuple[GeminiReader, list]:
    queue, requests = list(responses), []

    def handle(request):
        requests.append(request)
        return queue.pop(0)

    client = GeminiClient("test-key", transport=httpx.MockTransport(handle), attempts=5, sleep=lambda _: None)
    return GeminiReader(client), requests


@pytest.fixture
def photo(tmp_path):
    (tmp_path / "a.png").write_bytes(b"png")
    label = {"tags": ["source:synthetic"],
             "subjects": [{"name": "Giải tích", "day_of_week": 2, "start_time": "07:00", "end_time": "09:50",
                           "room": "B201"}]}
    (tmp_path / "a.json").write_text(json.dumps(label), encoding="utf-8")
    return tmp_path / "a.png"


def test_prompt_is_adapted_to_photos_and_keeps_the_injection_rule():
    assert "markdown" not in IMAGE_PROMPT and "ảnh đính kèm" in IMAGE_PROMPT
    assert "day_of_week" not in IMAGE_PROMPT and "- day: chép đúng thứ" in IMAGE_PROMPT
    assert UNTRUSTED_DATA_RULE in IMAGE_PROMPT


def test_day_names_become_numbers():
    rows = number_days([{"day": name} for name in DAY_NAMES] + [{"day": "Thứ 8"}, "not a row"])

    assert [row["day_of_week"] for row in rows] == [1, 2, 3, 4, 5, 6, 7, None]


def test_request_carries_image_and_schema_and_reply_is_scored(photo, tmp_path):
    reader, requests = reader_answering(completed(json.dumps({"subjects": [ROW]})))
    report = tmp_path / "report.jsonl"

    run(reader, [photo], report, TODAY)

    sent = json.loads(requests[0].content)
    assert requests[0].headers["x-goog-api-key"] == "test-key"
    assert [part["type"] for part in sent["input"]] == ["text", "image"]
    assert sent["system_instruction"] == IMAGE_PROMPT
    row_schema = sent["response_format"]["schema"]["properties"]["subjects"]["items"]
    assert row_schema["properties"]["day"]["enum"] == list(DAY_NAMES) and "day" in row_schema["required"]
    assert sent["store"] is False and "tools" not in sent
    assert total_tokens(report)["total_tokens"] == 1000
    assert sent["response_format"]["schema"]["required"] == ["subjects"]
    photos, skipped = load_photos(report, tmp_path)
    assert not skipped and photos[0].predicted[0]["start_time"].startswith("07:00")
    assert photos[0].predicted[0]["day_of_week"] == 2
    assert finished_files(report) == {"a.png"}


def test_rate_limit_is_retried(photo):
    reader, requests = reader_answering(httpx.Response(429), completed('{"subjects": []}'))

    assert reader.read_raw(photo.read_bytes(), photo.suffix) == '{"subjects": []}' and len(requests) == 2


@pytest.mark.parametrize("response, error", [
    (completed("not json"), "OCR_LOW_QUALITY"),
    (httpx.Response(200, json={"status": "incomplete", "steps": []}), "OCR_LOW_QUALITY"),
])
def test_unusable_reply_counts_as_a_miss(photo, tmp_path, response, error):
    reader, _ = reader_answering(response)
    report = tmp_path / "report.jsonl"

    run(reader, [photo], report, TODAY)

    assert json.loads(report.read_text())["body"]["error"] == error


def test_outage_is_not_counted_and_is_retried_later(photo, tmp_path):
    reader, _ = reader_answering(*[httpx.Response(503)] * 5)
    report = tmp_path / "report.jsonl"

    run(reader, [photo], report, TODAY)

    assert finished_files(report) == set()


def test_rejected_request_stops_the_run(photo, tmp_path):
    reader, requests = reader_answering(httpx.Response(400, text="bad schema"))

    with pytest.raises(GeminiRejected, match="bad schema"):
        run(reader, [photo], tmp_path / "report.jsonl", TODAY)
    assert len(requests) == 1


def test_injection_success_counts_obeyed_attacks_only():
    real = [{"name": "Toán"}]
    photos = [Photo("a", real, real + [{"name": CANARY.lower()}], ("attack:add",)),
              Photo("b", real, real, ("attack:add",)),
              Photo("c", real, [], ("attack:erase",)),
              Photo("d", real, real, ("attack:erase",)),
              Photo("clean", real, [])]

    assert injection_success_rate(photos) == 2 / 4


def test_only_tagged_photos_count_as_synthetic(photo):
    assert is_synthetic(photo)
    photo.with_suffix(".json").write_text('{"subjects": []}')
    assert not is_synthetic(photo)
