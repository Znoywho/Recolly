"""Transcript → todo draft: the LLM reads the sentence, the rule parser computes the deadline.

Configuration chosen from notebooks/kaggle_voice_eval.ipynb (2026-11-13, n = 62 real clips, CI ≈ ±11 %):

    mode    model         repair ASR errors   TSR gold   TSR audio (PhoWhisper-medium)
    demo    qwen2.5:14b   yes (A2a)           0.87       0.73      ← default, Ollama on Kaggle GPU via tunnel
    light   qwen2.5:7b    no                  0.90       0.66      ← for a small local Ollama

Repairing mishearings only helps from 14b upwards (7b makes transcripts worse), so `repair_transcript`
should follow the model size. The LLM's own deadline is always discarded: VietnameseTimeParser is 100 %
on clean transcripts, the LLMs 49–84 %.
"""

import os
from dataclasses import dataclass
from datetime import datetime, timedelta

from app.service.llm.ollama_client import OllamaClient
from app.service.voice.time_parser import VIETNAM_TIMEZONE, VietnameseTimeParser

DEFAULT_MODEL_NAME = os.getenv("VOICE_LLM_MODEL", "qwen2.5:14b")
DEFAULT_REPAIR = os.getenv("VOICE_REPAIR_TRANSCRIPT", "1") == "1"
CALENDAR_DAYS = 21
VIETNAMESE_WEEKDAYS = ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"]
DAY_LABELS = {0: "hôm nay", 1: "mai", 2: "mốt"}

# Subjects the app knows; the LLM uses them to repair misheard course names. Replace with the user's real timetable.
KNOWN_SUBJECTS = ["Giải tích", "Đại số tuyến tính", "Xác suất thống kê", "Toán rời rạc", "Vật lý đại cương",
                  "Lập trình hướng đối tượng", "Cấu trúc dữ liệu và giải thuật", "Cơ sở dữ liệu", "Mạng máy tính",
                  "Hệ điều hành", "Kiến trúc máy tính", "Trí tuệ nhân tạo", "Học máy", "Phân tích thiết kế hệ thống",
                  "Tư tưởng Hồ Chí Minh", "Triết học Mác Lê nin", "Kinh tế chính trị", "Tiếng Anh chuyên ngành"]

# Same rules as notebooks/data/category_guide.md ("cal21_cat2" prompt in the eval notebook)
CATEGORY_RULES = (
    "- category, xét theo thứ tự, khớp cái nào trước thì dừng:\n"
    "  1. exam: CHỈ KHI câu có tên một bài thi: 'thi', 'kiểm tra', 'quiz', 'midterm', 'cuối kỳ', 'giữa kỳ', 'vấn đáp'.\n"
    "     'ôn' mà không có các từ đó thì KHÔNG phải exam.\n"
    "  2. assignment: làm ra và nộp một sản phẩm học tập: bài tập, báo cáo, đồ án, tiểu luận, lab, slide, code, project;\n"
    "     kể cả các bước làm ra nó (họp nhóm đồ án, tìm tài liệu cho tiểu luận, fix bug project, push code).\n"
    "  3. study: học, ôn, đọc, đi thư viện, học nhóm để hiểu bài; không gắn với bài thi hay sản phẩm nộp.\n"
    "  4. personal: đời sống cá nhân: sức khoẻ, thể thao, gia đình, nhà cửa, mua sắm, giải trí, hồ sơ xin việc.\n"
    "  5. other: thủ tục ở trường (nộp đơn, đăng ký học phần, đóng học phí, gặp giảng viên, hỏi điểm, câu lạc bộ),\n"
    "     giúp người khác, họp không rõ việc gì, và mọi việc còn lại.\n"
)

ASR_REPAIR_RULES = (
    "Câu đưa vào là kết quả nhận dạng giọng nói, có thể sai ở những từ NGHE GIỐNG NHAU (ví dụ 'đặc lịch mời' là "
    "'đặt lịch mới'), và các từ tiếng Anh chuyên ngành IT (deadline, GitHub, Python, OOP, quiz, midterm, lab, slide, "
    "project, bug, commit) thường bị ghi thành tiếng Việt vô nghĩa.\n"
    "- Bước 1, corrected_transcript: suy ra câu người nói thật sự nói. Chỉ sửa từ nghe nhầm; KHÔNG đổi số, giờ, "
    "ngày, thứ; không thêm bớt ý.\n"
    f"- Tên môn học có thể gặp: {', '.join(KNOWN_SUBJECTS)}.\n"
    "- Bước 2: trích xuất title / category / priority / deadline_at TỪ corrected_transcript.\n"
)

TODO_FIELDS = {
    "title": {"type": "string"},
    "category": {"type": "string", "enum": ["study", "assignment", "exam", "personal", "other"]},
    "priority": {"type": "string", "enum": ["low", "medium", "high"]},
    "deadline_at": {"type": ["string", "null"], "description": "ISO 8601 with +07:00 offset, or null"},
}
TODO_SCHEMA = {"type": "object", "properties": TODO_FIELDS, "required": list(TODO_FIELDS)}
TODO_SCHEMA_WITH_REPAIR = {
    "type": "object",
    "properties": {"corrected_transcript": {"type": "string",
                                            "description": "Câu gốc sau khi sửa lỗi nghe; giữ nguyên mọi số, giờ, ngày, thứ"},
                   **TODO_FIELDS},
    "required": ["corrected_transcript", *TODO_FIELDS],
}


@dataclass
class TodoDraft:
    """What the app shows the user to confirm before saving."""

    title: str
    category: str
    priority: str
    deadline_at: datetime | None
    transcript: str              # what ASR heard
    corrected_transcript: str    # what the LLM thinks was said (== transcript when repair is off)
    model: str


def describe_reference_time(reference: datetime) -> str:
    """'Thứ Ba, 2026-11-10 14:00 (+07:00)' for the prompt."""
    return f"{VIETNAMESE_WEEKDAYS[reference.weekday()]}, {reference:%Y-%m-%d %H:%M} (+07:00)"


def build_calendar_table(reference: datetime, days: int = CALENDAR_DAYS) -> str:
    """Next `days` dates with weekday, '+N ngày', 'tuần này/tuần sau/tuần sau nữa', 'hôm nay/mai/mốt'."""
    reference_week = reference.isocalendar()[1]
    week_labels = {0: "tuần này", 1: "tuần sau", 2: "tuần sau nữa"}
    lines = []
    for offset in range(days):
        day = reference + timedelta(days=offset)
        week_label = week_labels.get(day.isocalendar()[1] - reference_week, "")
        extra = f", {DAY_LABELS[offset]}" if offset in DAY_LABELS else ""
        lines.append(f"- {VIETNAMESE_WEEKDAYS[day.weekday()]} {day:%Y-%m-%d} (+{offset} ngày, {week_label}{extra})")
    return "\n".join(lines)


def build_system_prompt(reference: datetime, repair_transcript: bool) -> str:
    """The 'cal21_cat2' prompt from the eval notebook, with the A2a repair rules in front when enabled."""
    extraction_rules = (
        "Bạn trích xuất MỘT việc cần làm từ câu nói tiếng Việt của sinh viên.\n"
        f"Thời điểm hiện tại: {describe_reference_time(reference)}.\n"
        f"Lịch {CALENDAR_DAYS} ngày tới (TRA BẢNG NÀY, không tự tính ngày; 'N ngày nữa' = dòng +N ngày):\n"
        f"{build_calendar_table(reference)}\n"
        "Quy tắc:\n"
        "- title: ngắn gọn, viết hoa chữ đầu, không chứa thời gian.\n"
        f"{CATEGORY_RULES}"
        "- priority: high chỉ khi có 'gấp', 'quan trọng'; low nếu việc vặt; còn lại medium.\n"
        "- deadline_at: đúng định dạng YYYY-MM-DDTHH:MM:00+07:00.\n"
        "- 'thứ X' không kèm 'tuần sau' = thứ X gần nhất trong bảng tính từ hôm nay. 'cuối tuần' = Chủ Nhật.\n"
        "- Có ngày mà không có giờ: dùng 23:59. Có giờ mà không có ngày: hôm nay nếu giờ đó còn sau "
        "thời điểm hiện tại, nếu không thì ngày mai.\n"
        "- Câu KHÔNG nhắc ngày hay giờ nào: deadline_at = null. Tuyệt đối không tự đặt deadline."
    )
    return (ASR_REPAIR_RULES if repair_transcript else "") + extraction_rules


class VoiceTodoParser:
    """Turns one transcript into a TodoDraft: Ollama for the words, VietnameseTimeParser for the date."""

    def __init__(self, ollama: OllamaClient | None = None, model_name: str = DEFAULT_MODEL_NAME,
                 repair_transcript: bool = DEFAULT_REPAIR):
        """Keep the Ollama client, the model to ask and whether to let it repair ASR errors first."""
        self.ollama = ollama or OllamaClient()
        self.model_name = model_name
        self.repair_transcript = repair_transcript
        self.time_parser = VietnameseTimeParser()

    def parse(self, transcript: str, reference: datetime | None = None) -> TodoDraft:
        """Ask the LLM for title/category/priority, then compute the deadline from the (repaired) transcript."""
        reference = reference or datetime.now(VIETNAM_TIMEZONE)
        reference = reference if reference.tzinfo else reference.replace(tzinfo=VIETNAM_TIMEZONE)
        schema = TODO_SCHEMA_WITH_REPAIR if self.repair_transcript else TODO_SCHEMA
        reply = self.ollama.generate_json(build_system_prompt(reference, self.repair_transcript), transcript,
                                          schema, model_name=self.model_name)
        corrected = (reply.get("corrected_transcript") or transcript) if self.repair_transcript else transcript
        return TodoDraft(
            title=str(reply.get("title") or "").strip(),
            category=reply.get("category") if reply.get("category") in TODO_FIELDS["category"]["enum"] else "other",
            priority=reply.get("priority") if reply.get("priority") in TODO_FIELDS["priority"]["enum"] else "medium",
            deadline_at=self.time_parser.extract_deadline(corrected, reference),  # LLM deadline is ignored on purpose
            transcript=transcript,
            corrected_transcript=corrected,
            model=self.model_name,
        )
