"""Vintern's markdown timetable → OcrSubject rows (R11).

Ollama only copies what the table shows (day, clock times or periods, room, dates). Turning periods
into clock times and filling missing dates is plain code, so it gives the same answer on every run.
"""

import os
import re
from datetime import date, time, timedelta

from pydantic import ValidationError

from app.schemas.timetable import OcrSubject
from app.service.llm.ollama_client import OllamaClient
from app.service.voice.todo_parser import DEFAULT_MODEL_NAME

# Period number -> (start, end).
# shortcut: placeholder times until the team's real period table is filled in; replace before the demo.
PERIOD_TIMES: dict[int, tuple[time, time]] = {
    1: (time(7, 0), time(7, 50)), 2: (time(7, 50), time(8, 40)), 3: (time(9, 0), time(9, 50)),
    4: (time(9, 50), time(10, 40)), 5: (time(10, 40), time(11, 30)), 6: (time(13, 0), time(13, 50)),
    7: (time(13, 50), time(14, 40)), 8: (time(15, 0), time(15, 50)), 9: (time(15, 50), time(16, 40)),
    10: (time(16, 40), time(17, 30)), 11: (time(18, 0), time(18, 50)), 12: (time(18, 50), time(19, 40)),
    13: (time(19, 40), time(20, 30)),
}
# A full timetable is ~1500 JSON tokens: more than the 60 s Ollama default on a T4.
LLM_TIMEOUT_SECONDS = float(os.getenv("OCR_LLM_TIMEOUT_SECONDS", "180"))
SEMESTER_WEEKS = 15        # used when the photo shows no end date
READ_CONFIDENCE = 0.9      # every field came from the photo
FILLED_CONFIDENCE = 0.6    # a date was missing and filled in: the user should check it

NULLABLE_TEXT = {"type": ["string", "null"]}
ROW_FIELDS = {
    "name": {"type": "string", "description": "Tên môn học"},
    "code": {**NULLABLE_TEXT, "description": "Mã môn / mã lớp"},
    "room": {**NULLABLE_TEXT, "description": "Phòng học"},
    "lecturer": {**NULLABLE_TEXT, "description": "Giảng viên"},
    "day_of_week": {"type": "integer", "minimum": 1, "maximum": 7, "description": "Thứ 2 = 1 ... Chủ nhật = 7"},
    "start_time": {**NULLABLE_TEXT, "description": "HH:MM nếu bảng ghi giờ, ngược lại null"},
    "end_time": {**NULLABLE_TEXT, "description": "HH:MM nếu bảng ghi giờ, ngược lại null"},
    "start_period": {"type": ["integer", "null"], "description": "Tiết bắt đầu nếu bảng ghi tiết"},
    "end_period": {"type": ["integer", "null"], "description": "Tiết kết thúc nếu bảng ghi tiết"},
    "start_date": {**NULLABLE_TEXT, "description": "YYYY-MM-DD ngày học đầu tiên, null nếu không có"},
    "end_date": {**NULLABLE_TEXT, "description": "YYYY-MM-DD ngày học cuối cùng, null nếu không có"},
}
TIMETABLE_SCHEMA = {
    "type": "object",
    "properties": {"subjects": {"type": "array", "items": {
        "type": "object", "properties": ROW_FIELDS, "required": list(ROW_FIELDS)}}},
    "required": ["subjects"],
}
SYSTEM_PROMPT = (
    "Bạn đọc bảng thời khoá biểu của sinh viên Việt Nam (dạng markdown, do OCR đọc từ ảnh nên có thể lỗi chính tả) "
    "và trả về mỗi buổi học là MỘT dòng trong subjects.\n"
    "Quy tắc:\n"
    "- day_of_week: Thứ 2 = 1, Thứ 3 = 2, Thứ 4 = 3, Thứ 5 = 4, Thứ 6 = 5, Thứ 7 = 6, Chủ nhật (CN) = 7.\n"
    "- Một môn học nhiều buổi trong tuần → mỗi buổi một dòng.\n"
    "- Bảng ghi giờ (ví dụ 07:30 - 09:30) → điền start_time/end_time, để start_period/end_period = null.\n"
    "- Bảng ghi tiết (ví dụ 'Tiết 1-3' hoặc '1→3') → điền start_period/end_period, để start_time/end_time = null.\n"
    "- Ngày dạng dd/mm/yyyy → đổi sang YYYY-MM-DD.\n"
    "- Chỉ chép những gì có trong bảng. Trường nào không có → null. Không bịa môn học.\n"
    "- Không có bảng thời khoá biểu nào → subjects = []."
)
_CLOCK = re.compile(r"(\d{1,2})\s*[:hH]\s*(\d{2})")


def parse_clock(value: object) -> time | None:
    """'7:30', '07:30' or '7h30' -> time(7, 30); anything else -> None."""
    match = _CLOCK.fullmatch(str(value).strip()) if value else None
    if not match or int(match[1]) > 23 or int(match[2]) > 59:
        return None
    return time(int(match[1]), int(match[2]))


def parse_day(value: object) -> date | None:
    """'2026-09-07' -> date; anything else -> None."""
    try:
        return date.fromisoformat(str(value)) if value else None
    except ValueError:
        return None


def row_to_subject(row: dict, today: date) -> OcrSubject | None:
    """One LLM row -> OcrSubject, or None when the row has no usable time or fails validation."""
    start, end = parse_clock(row.get("start_time")), parse_clock(row.get("end_time"))
    if start is None or end is None:
        first, last = PERIOD_TIMES.get(row.get("start_period")), PERIOD_TIMES.get(row.get("end_period"))
        if first is None or last is None:
            return None
        start, end = first[0], last[1]
    start_date, end_date = parse_day(row.get("start_date")), parse_day(row.get("end_date"))
    filled = start_date is None or end_date is None
    # shortcut: a missing date becomes this semester from today; the user fixes it on the review screen (R14).
    start_date = start_date or today
    end_date = end_date or start_date + timedelta(weeks=SEMESTER_WEEKS)
    try:
        return OcrSubject(name=str(row.get("name") or "").strip(), code=row.get("code"), room=row.get("room"),
                          lecturer=row.get("lecturer"), day_of_week=row.get("day_of_week"),
                          start_time=start, end_time=end, start_date=start_date, end_date=end_date,
                          confidence=FILLED_CONFIDENCE if filled else READ_CONFIDENCE)
    except ValidationError:
        return None


def rows_to_subjects(rows: list[dict], today: date) -> list[OcrSubject]:
    """Every usable row, in table order; broken rows are dropped (the user can add them by hand)."""
    subjects = (row_to_subject(row, today) for row in rows if isinstance(row, dict))
    return [subject for subject in subjects if subject is not None]


class TimetableParser:
    """Asks Ollama to turn Vintern's markdown into rows, then converts them to OcrSubject."""

    def __init__(self, ollama: OllamaClient | None = None, model_name: str = DEFAULT_MODEL_NAME):
        """Keep the Ollama client and the model (same one the voice parser uses)."""
        self.ollama = ollama or OllamaClient(timeout_seconds=LLM_TIMEOUT_SECONDS)
        self.model_name = model_name

    def parse(self, markdown: str, today: date) -> list[OcrSubject]:
        """Return the subjects found in the markdown table (empty when there is no timetable)."""
        reply = self.ollama.generate_json(SYSTEM_PROMPT, markdown, TIMETABLE_SCHEMA, model_name=self.model_name)
        rows = reply.get("subjects")
        return rows_to_subjects(rows if isinstance(rows, list) else [], today)
