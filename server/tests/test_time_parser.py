"""Checks for the rule-based Vietnamese deadline parser.

The sentences here are deliberately NOT taken from notebooks/data/voice_eval.jsonl, so the eval set
stays an honest held-out test of the parser.
"""

from datetime import datetime

import pytest

from app.service.voice.time_parser import (
    VIETNAM_TIMEZONE,
    VietnameseTimeParser,
    parse_vietnamese_number,
    to_24_hour,
)

# Reference moments: a Tuesday afternoon and a Sunday late evening
TUESDAY_2PM = datetime(2026, 11, 10, 14, 0, tzinfo=VIETNAM_TIMEZONE)
SUNDAY_10PM = datetime(2026, 11, 15, 22, 0, tzinfo=VIETNAM_TIMEZONE)


@pytest.mark.parametrize("words, value", [
    ("bảy", 7), ("mười", 10), ("mười một", 11), ("mười lăm", 15), ("mười chín", 19),
    ("hai mươi", 20), ("hai mươi mốt", 21), ("hai mươi tư", 24), ("ba mươi", 30), ("19", 19),
])
def test_parse_vietnamese_number(words, value):
    assert parse_vietnamese_number(words.split()) == value


@pytest.mark.parametrize("words", ["học", "mười mốt", "mốt", "hai ba", ""])
def test_parse_vietnamese_number_rejects_non_numbers(words):
    assert parse_vietnamese_number(words.split()) is None


@pytest.mark.parametrize("hour, part, expected", [
    (7, "sáng", 7), (7, "tối", 19), (3, "chiều", 15), (12, "trưa", 12), (1, "trưa", 13),
    (11, "đêm", 23), (2, "đêm", 2), (17, None, 17), (9, None, 9),
])
def test_to_24_hour(hour, part, expected):
    assert to_24_hour(hour, part) == expected


@pytest.mark.parametrize("sentence, reference, expected", [
    # clock only: today if still ahead, otherwise tomorrow
    ("chín giờ tối gọi cho bạn", TUESDAY_2PM, "2026-11-10 21:00"),
    ("lúc bảy giờ sáng tập gym", TUESDAY_2PM, "2026-11-11 07:00"),
    ("mười giờ rưỡi đêm đọc truyện", TUESDAY_2PM, "2026-11-10 22:30"),
    ("chín giờ kém mười lăm tối họp online", TUESDAY_2PM, "2026-11-10 20:45"),
    ("hai mươi giờ mười phút xem phim", TUESDAY_2PM, "2026-11-10 20:10"),
    ("1 giờ chiều đi khám răng", TUESDAY_2PM, "2026-11-11 13:00"),
    ("19h30 đá banh", TUESDAY_2PM, "2026-11-10 19:30"),
    ("lúc bốn rưỡi chiều đi bơi", TUESDAY_2PM, "2026-11-10 16:30"),
    ("sáu rưỡi sáng chạy bộ", TUESDAY_2PM, "2026-11-11 06:30"),
    # relative days
    ("hôm nay trả sách thư viện", TUESDAY_2PM, "2026-11-10 23:59"),
    ("sáng mai tám giờ rưỡi thi vấn đáp", TUESDAY_2PM, "2026-11-11 08:30"),
    ("mốt nộp bài thu hoạch", TUESDAY_2PM, "2026-11-12 23:59"),
    ("ngày kia đi khám sức khỏe", TUESDAY_2PM, "2026-11-12 23:59"),
    ("năm ngày nữa nộp đồ án", TUESDAY_2PM, "2026-11-15 23:59"),
    ("một tuần nữa thi cuối kỳ", TUESDAY_2PM, "2026-11-17 23:59"),
    # weekdays
    ("thứ bảy này đi siêu thị", TUESDAY_2PM, "2026-11-14 23:59"),
    ("thứ ba thuyết trình", TUESDAY_2PM, "2026-11-10 23:59"),
    ("thứ hai họp lớp", SUNDAY_10PM, "2026-11-16 23:59"),
    ("tuần tới thứ sáu nộp bài", TUESDAY_2PM, "2026-11-20 23:59"),
    ("thứ 6 tuần sau nữa thi", TUESDAY_2PM, "2026-11-27 23:59"),
    ("chủ nhật chín giờ sáng chạy bộ", TUESDAY_2PM, "2026-11-15 09:00"),
    ("cuối tuần giặt chăn", SUNDAY_10PM, "2026-11-15 23:59"),
    # calendar dates
    ("ngày hai mươi tám tháng mười một nộp báo cáo", TUESDAY_2PM, "2026-11-28 23:59"),
    ("mùng năm tháng một thi", TUESDAY_2PM, "2027-01-05 23:59"),
    ("ngày ba mươi đóng tiền nhà", TUESDAY_2PM, "2026-11-30 23:59"),
    # no time at all
    ("mua sổ tay mới", TUESDAY_2PM, None),
    ("bây giờ phải học bài", TUESDAY_2PM, None),
    ("ôn tư tưởng hồ chí minh", TUESDAY_2PM, None),
    ("kiểm tra mười lăm phút môn hóa", TUESDAY_2PM, None),
    ("học tiếng nhật được một năm rưỡi", TUESDAY_2PM, None),
])
def test_extract_deadline(sentence, reference, expected):
    deadline = VietnameseTimeParser().extract_deadline(sentence, reference)
    assert (deadline.strftime("%Y-%m-%d %H:%M") if deadline else None) == expected


def test_matched_phrases_explain_the_result():
    expression = VietnameseTimeParser().parse("tối thứ sáu này tám giờ ôn thi")
    assert expression.date_type == "weekday" and expression.weekday == 4
    assert (expression.hour, expression.minute) == (20, 0)
    assert expression.matched == ["tám giờ", "thứ sáu"]
