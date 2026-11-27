"""Timetable photo -> subjects with Gemini: one call reads the picture and returns JSON rows.

Gemini returns the weekday as written ("Thứ 5") and code turns it into 1-7: asked for a number, it copied
the 5 (55% correct weekdays on the synthetic dev set, 99.7% with text).
"""

import copy
import json
from datetime import date

from app.schemas.timetable import OcrSubject
from app.service.llm.gemini_client import GeminiClient
from app.service.ocr.timetable_parser import SYSTEM_PROMPT, TIMETABLE_SCHEMA, rows_to_subjects

MIME_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".heic": "image/heic"}
DAY_NAMES = ("Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7", "Chủ nhật")  # index + 1 = day_of_week
NUMBER_DAY_RULE = "- day_of_week: Thứ 2 = 1, Thứ 3 = 2, Thứ 4 = 3, Thứ 5 = 4, Thứ 6 = 5, Thứ 7 = 6, Chủ nhật (CN) = 7.\n"
TEXT_DAY_RULE = "- day: chép đúng thứ của buổi học: " + ", ".join(DAY_NAMES) + " (CN = Chủ nhật).\n"
# The markdown parser's rules, with the input sentence changed to a photo and the weekday asked as text.
IMAGE_PROMPT = SYSTEM_PROMPT.replace(
    "(dạng markdown, do OCR đọc từ ảnh nên có thể lỗi chính tả)", "(trong ảnh đính kèm)").replace(
    NUMBER_DAY_RULE, TEXT_DAY_RULE)
USER_REQUEST = "Đọc thời khoá biểu trong ảnh này."


def text_day_schema() -> dict:
    """A copy of TIMETABLE_SCHEMA whose rows give `day` (one of DAY_NAMES) instead of `day_of_week`."""
    schema = copy.deepcopy(TIMETABLE_SCHEMA)
    row = schema["properties"]["subjects"]["items"]
    row["properties"] = {("day" if key == "day_of_week" else key): value for key, value in row["properties"].items()}
    row["properties"]["day"] = {"type": "string", "enum": list(DAY_NAMES), "description": "Thứ ghi trong bảng"}
    row["required"] = list(row["properties"])
    return schema


def number_days(rows: object) -> list[dict]:
    """Rows with `day_of_week` computed from the `day` text; an unknown day stays None and is dropped later."""
    if not isinstance(rows, list):
        return []
    numbers = {name: number for number, name in enumerate(DAY_NAMES, 1)}
    return [{**row, "day_of_week": numbers.get(str(row.get("day")))} for row in rows if isinstance(row, dict)]


IMAGE_SCHEMA = text_day_schema()


class GeminiReader:
    """Reads a timetable photo with Gemini (same two steps as VinternReader)."""

    def __init__(self, client: GeminiClient):
        """Keep the client that talks to Gemini."""
        self.client = client

    def read_raw(self, image_bytes: bytes, suffix: str) -> str:
        """Gemini's reply as JSON text (kept on the job for the accuracy check)."""
        reply = self.client.generate_json_from_image(IMAGE_PROMPT, USER_REQUEST, image_bytes,
                                                     MIME_TYPES[suffix.lower()], IMAGE_SCHEMA)
        return json.dumps(reply, ensure_ascii=False)

    def parse(self, raw: str, today: date) -> list[OcrSubject]:
        """Validated subjects from the reply (periods to clock times, missing dates filled)."""
        return rows_to_subjects(number_days(json.loads(raw).get("subjects")), today)
