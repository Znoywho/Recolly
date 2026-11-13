"""Checks for VoiceTodoParser with a fake Ollama server (httpx MockTransport), no model needed."""

import json
from datetime import datetime

import httpx

from app.service.llm.ollama_client import OllamaClient
from app.service.voice.time_parser import VIETNAM_TIMEZONE
from app.service.voice.todo_parser import TODO_SCHEMA, TODO_SCHEMA_WITH_REPAIR, VoiceTodoParser, build_system_prompt

TUESDAY_2PM = datetime(2026, 11, 10, 14, 0, tzinfo=VIETNAM_TIMEZONE)


def fake_ollama(reply: dict, seen: list[dict]) -> OllamaClient:
    """An OllamaClient whose /api/chat always answers `reply` and records the request payloads."""
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(json.loads(request.content))
        return httpx.Response(200, json={"message": {"content": json.dumps(reply, ensure_ascii=False)}})
    return OllamaClient(base_url="http://fake", transport=httpx.MockTransport(handler))


def test_repair_mode_uses_corrected_transcript_for_the_deadline():
    seen = []
    reply = {"corrected_transcript": "chiều mai push code lên GitHub trước năm giờ", "title": "Push code lên GitHub",
             "category": "assignment", "priority": "medium", "deadline_at": "2099-01-01T00:00:00+07:00"}
    parser = VoiceTodoParser(fake_ollama(reply, seen), model_name="qwen2.5:14b", repair_transcript=True)

    draft = parser.parse("chiều mai bush scott lên kết thúc trước năm giờ", TUESDAY_2PM)

    assert draft.title == "Push code lên GitHub" and draft.category == "assignment"
    assert draft.corrected_transcript == "chiều mai push code lên GitHub trước năm giờ"
    assert draft.deadline_at == datetime(2026, 11, 11, 17, 0, tzinfo=VIETNAM_TIMEZONE)  # rules, not the LLM's 2099
    assert seen[0]["model"] == "qwen2.5:14b" and seen[0]["format"] == TODO_SCHEMA_WITH_REPAIR
    assert seen[0]["messages"][0]["content"].startswith("Câu đưa vào là kết quả nhận dạng giọng nói")


def test_light_mode_skips_repair_and_keeps_raw_transcript():
    seen = []
    reply = {"title": "Ôn thi giải tích", "category": "exam", "priority": "medium", "deadline_at": None}
    parser = VoiceTodoParser(fake_ollama(reply, seen), model_name="qwen2.5:7b", repair_transcript=False)

    draft = parser.parse("tối thứ sáu này tám giờ ôn thi giải tích", TUESDAY_2PM)

    assert draft.corrected_transcript == draft.transcript
    assert draft.deadline_at == datetime(2026, 11, 13, 20, 0, tzinfo=VIETNAM_TIMEZONE)
    assert seen[0]["format"] == TODO_SCHEMA and "corrected_transcript" not in seen[0]["format"]["properties"]


def test_sentence_without_time_gets_no_deadline_even_if_the_llm_invents_one():
    reply = {"title": "Mua sách giáo trình", "category": "personal", "priority": "low",
             "deadline_at": "2026-11-15T23:59:00+07:00"}
    draft = VoiceTodoParser(fake_ollama(reply, []), repair_transcript=False).parse("mua sách giáo trình", TUESDAY_2PM)
    assert draft.deadline_at is None


def test_invalid_enum_values_fall_back():
    reply = {"title": "X", "category": "homework", "priority": "urgent", "deadline_at": None}
    draft = VoiceTodoParser(fake_ollama(reply, []), repair_transcript=False).parse("x", TUESDAY_2PM)
    assert (draft.category, draft.priority) == ("other", "medium")


def test_prompt_contains_calendar_and_category_rules():
    prompt = build_system_prompt(TUESDAY_2PM, repair_transcript=False)
    assert "Thứ Ba, 2026-11-10 14:00" in prompt
    assert "- Thứ Ba 2026-11-24 (+14 ngày, tuần sau nữa)" in prompt
    assert "1. exam: CHỈ KHI" in prompt
