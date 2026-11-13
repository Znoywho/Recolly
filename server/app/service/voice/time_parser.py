"""Rule-based deadline extraction from Vietnamese todo sentences (no ML, microseconds per sentence).

The LLM is good at language (title, category) but bad at calendar arithmetic, so time expressions are
handled here with a small closed vocabulary instead:

    "tối thứ sáu này tám giờ"  → weekday=4, clock 20:00          → Fri 20:00
    "chiều mai bốn giờ"        → day_offset=1, clock 16:00        → tomorrow 16:00
    "hai tuần nữa"             → day_offset=14                    → today + 14 days, 23:59
    "lúc sáu giờ sáng"         → clock 06:00 only                 → next 06:00 (today or tomorrow)
    "mua sách giáo trình"      → nothing found                    → no deadline (None)

Self-contained (standard library only) so it can also be pasted into the evaluation notebook.
"""

import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from datetime import time as clock_time

VIETNAM_TIMEZONE = timezone(timedelta(hours=7))
END_OF_DAY = clock_time(23, 59)

UNIT_WORDS = {"không": 0, "một": 1, "hai": 2, "ba": 3, "bốn": 4, "năm": 5, "sáu": 6, "bảy": 7, "tám": 8, "chín": 9}
UNIT_WORDS_AFTER_TENS = {**UNIT_WORDS, "mốt": 1, "tư": 4, "lăm": 5, "nhăm": 5}  # "hai mươi mốt", "mười lăm"
TENS_MARKERS = {"mươi", "chục"}
WEEKDAY_WORDS = {"hai": 0, "ba": 1, "tư": 2, "bốn": 2, "năm": 3, "sáu": 4, "bảy": 5}  # after "thứ"; Monday = 0
PARTS_OF_DAY = {"sáng", "trưa", "chiều", "tối", "đêm", "khuya"}
RELATIVE_DAY_WORDS = {"nay": 0, "mai": 1, "mốt": 2}


@dataclass
class TimeExpression:
    """Time information found in one sentence, before it is turned into a concrete datetime."""

    date_type: str = "none"          # none | relative_days | weekday | calendar_date
    day_offset: int | None = None
    weekday: int | None = None       # Monday = 0 ... Sunday = 6
    week_offset: int = 0             # 1 = "tuần sau", 2 = "tuần sau nữa"
    day_of_month: int | None = None
    month: int | None = None
    hour: int | None = None          # 24h, after applying the part of day
    minute: int = 0
    matched: list[str] = field(default_factory=list)  # phrases that triggered each rule (for debugging)

    def has_clock(self) -> bool:
        """True when a clock time was found."""
        return self.hour is not None


def normalize_sentence(text: str) -> list[str]:
    """NFC-normalize, lowercase, split '8h30' / '19:30' into words and return the tokens without punctuation."""
    text = unicodedata.normalize("NFC", text).lower()
    text = re.sub(r"(\d{1,2})\s*[h:]\s*(\d{2})\b", r"\1 giờ \2", text)  # 8h30, 19:30 → 8 giờ 30
    text = re.sub(r"(\d{1,2})\s*h\b", r"\1 giờ", text)                  # 19h → 19 giờ
    text = re.sub(r"[^\w\s]", " ", text)
    return text.split()


def parse_vietnamese_number(tokens: list[str]) -> int | None:
    """Spoken Vietnamese number made of exactly these tokens (0..99), or None.

    "bảy" = 7 · "mười" = 10 · "mười lăm" = 15 · "hai mươi" = 20 · "hai mươi mốt" = 21 · "19" = 19
    value = tens · 10 + units   ("mười" alone means tens = 1)
    """
    if not tokens:
        return None
    if len(tokens) == 1 and tokens[0].isdigit():
        return int(tokens[0])
    if len(tokens) == 1:
        return UNIT_WORDS.get(tokens[0]) if tokens[0] != "mười" else 10
    if tokens[0] == "mười":
        tens, rest = 1, tokens[1:]
    elif tokens[0] in UNIT_WORDS and tokens[1] in TENS_MARKERS:
        tens, rest = UNIT_WORDS[tokens[0]], tokens[2:]
    else:
        return None
    if not rest:
        return tens * 10
    if len(rest) == 1 and rest[0] in UNIT_WORDS_AFTER_TENS:
        unit = UNIT_WORDS_AFTER_TENS[rest[0]]
        if rest[0] == "mốt" and tens < 2:  # "mười mốt" is not a number, "mười một" is
            return None
        return tens * 10 + unit
    return None


def longest_number_ending_at(tokens: list[str], end: int, max_length: int = 3) -> tuple[int, int] | None:
    """Longest number whose last token is tokens[end - 1]; returns (value, start index) or None."""
    for length in range(max_length, 0, -1):
        start = end - length
        if start >= 0:
            value = parse_vietnamese_number(tokens[start:end])
            if value is not None:
                return value, start
    return None


def longest_number_starting_at(tokens: list[str], start: int, max_length: int = 3) -> tuple[int, int] | None:
    """Longest number whose first token is tokens[start]; returns (value, end index) or None."""
    for length in range(max_length, 0, -1):
        end = start + length
        if end <= len(tokens):
            value = parse_vietnamese_number(tokens[start:end])
            if value is not None:
                return value, end
    return None


def to_24_hour(hour: int, part_of_day: str | None) -> int:
    """Apply the spoken part of day to a 12h clock hour.

    chiều/tối: h < 12 → h + 12 · trưa: h ≤ 4 → h + 12 (một giờ trưa = 13) · đêm/khuya: 6 ≤ h < 12 → h + 12
    sáng or no part of day: unchanged
    """
    if hour >= 13 or part_of_day is None or part_of_day == "sáng":
        return hour
    if part_of_day in ("chiều", "tối"):
        return hour + 12 if hour < 12 else hour
    if part_of_day == "trưa":
        return hour + 12 if hour <= 4 else hour
    if part_of_day in ("đêm", "khuya"):
        return hour + 12 if 6 <= hour < 12 else hour
    return hour


def date_from_weekday(reference_day: date, weekday: int, week_offset: int) -> date:
    """Named weekday, optionally in a later week (Monday = 0 ... Sunday = 6).

    monday = reference_date − reference_date.weekday()
    date   = monday + 7·week_offset + weekday
    if week_offset = 0 and date < reference_date: date += 7   (that day already passed this week)
    """
    monday = reference_day - timedelta(days=reference_day.weekday())
    target = monday + timedelta(days=7 * week_offset + weekday)
    if week_offset == 0 and target < reference_day:
        target += timedelta(days=7)
    return target


def date_from_day_and_month(reference_day: date, day_of_month: int, month: int | None) -> date | None:
    """Explicit 'ngày N (tháng M)': the next such date on or after today; None if it does not exist."""
    try:
        if month is None:
            target = reference_day.replace(day=day_of_month)
            if target < reference_day:
                next_month_first = (reference_day.replace(day=1) + timedelta(days=32)).replace(day=1)
                target = next_month_first.replace(day=day_of_month)
            return target
        target = date(reference_day.year, month, day_of_month)
        return target if target >= reference_day else date(reference_day.year + 1, month, day_of_month)
    except ValueError:  # 31/2, day 31 in a 30-day month, ...
        return None


class VietnameseTimeParser:
    """Finds time expressions in a Vietnamese sentence and turns them into a deadline."""

    def parse(self, text: str) -> TimeExpression:
        """Extract date and clock information from one sentence (no reference time needed yet)."""
        tokens = normalize_sentence(text)
        expression = TimeExpression()
        self._find_clock(tokens, expression)
        if not self._find_calendar_date(tokens, expression):
            if not self._find_relative_days(tokens, expression):
                self._find_weekday(tokens, expression)
        return expression

    def resolve(self, expression: TimeExpression, reference: datetime) -> datetime | None:
        """Turn a TimeExpression into an absolute deadline (+07:00), or None when no time was said.

        calendar_date → that date · relative_days → today + day_offset · weekday → see date_from_weekday
        clock only    → today if that time is still ahead, otherwise tomorrow
        clock: the spoken time, or 23:59 when only a day was said
        """
        reference = reference if reference.tzinfo else reference.replace(tzinfo=VIETNAM_TIMEZONE)
        reference = reference.astimezone(VIETNAM_TIMEZONE)
        today = reference.date()
        clock = clock_time(expression.hour, expression.minute) if expression.has_clock() else None

        if expression.date_type == "calendar_date":
            target_day = date_from_day_and_month(today, expression.day_of_month, expression.month)
        elif expression.date_type == "relative_days":
            target_day = today + timedelta(days=expression.day_offset)
        elif expression.date_type == "weekday":
            target_day = date_from_weekday(today, expression.weekday, expression.week_offset)
        elif clock is not None:
            today_at_clock = datetime.combine(today, clock, VIETNAM_TIMEZONE)
            target_day = today if today_at_clock > reference else today + timedelta(days=1)
        else:
            return None

        if target_day is None:
            return None
        return datetime.combine(target_day, clock or END_OF_DAY, VIETNAM_TIMEZONE)

    def extract_deadline(self, text: str, reference: datetime) -> datetime | None:
        """parse() + resolve() in one call."""
        return self.resolve(self.parse(text), reference)

    # --- rules -------------------------------------------------------------------------------------

    def _find_clock(self, tokens: list[str], expression: TimeExpression) -> None:
        """'<number> giờ [rưỡi | <number> (phút) | kém <number> (phút)]' + nearest part of day."""
        for index, token in enumerate(tokens):
            if token != "giờ":
                continue
            hour_match = longest_number_ending_at(tokens, index)
            if hour_match is None or not 0 <= hour_match[0] <= 24:
                continue  # "bây giờ", "giờ học", ...
            hour, minute, after = hour_match[0], 0, index + 1
            if after < len(tokens) and tokens[after] == "rưỡi":
                minute, after = 30, after + 1
            elif after < len(tokens) and tokens[after] == "kém":
                minutes_before = longest_number_starting_at(tokens, after + 1, max_length=2)
                if minutes_before and 0 < minutes_before[0] < 60:
                    hour, minute, after = (hour - 1) % 24, 60 - minutes_before[0], minutes_before[1]
            else:
                minutes_match = longest_number_starting_at(tokens, after, max_length=3)
                if minutes_match and 0 <= minutes_match[0] < 60:
                    minute, after = minutes_match[0], minutes_match[1]
            if after < len(tokens) and tokens[after] == "phút":
                after += 1
            expression.hour = to_24_hour(hour, self._nearest_part_of_day(tokens, index))
            expression.minute = minute
            expression.matched.append(" ".join(tokens[hour_match[1]:after]))
            return
        self._find_half_hour_without_gio(tokens, expression)

    def _find_half_hour_without_gio(self, tokens: list[str], expression: TimeExpression) -> None:
        """'(lúc) <number> rưỡi <part of day>' without the word 'giờ', e.g. 'lúc ba rưỡi chiều' = 15:30.

        Needs 'lúc' before or a part of day right after, so 'một năm rưỡi' (1.5 years) is not a clock.
        """
        for index, token in enumerate(tokens):
            if token != "rưỡi":
                continue
            hour_match = longest_number_ending_at(tokens, index, max_length=2)
            if hour_match is None or not 1 <= hour_match[0] <= 12:
                continue
            before = tokens[hour_match[1] - 1] if hour_match[1] > 0 else ""
            after = tokens[index + 1] if index + 1 < len(tokens) else ""
            if before != "lúc" and after not in PARTS_OF_DAY:
                continue
            expression.hour = to_24_hour(hour_match[0], self._nearest_part_of_day(tokens, index))
            expression.minute = 30
            expression.matched.append(" ".join(tokens[hour_match[1]:index + 1]))
            return

    @staticmethod
    def _nearest_part_of_day(tokens: list[str], clock_index: int) -> str | None:
        """The part-of-day word (sáng/trưa/chiều/tối/đêm) closest to the clock, preferring the one after it."""
        positions = [i for i, token in enumerate(tokens) if token in PARTS_OF_DAY]
        if not positions:
            return None
        closest = min(positions, key=lambda i: (abs(i - clock_index), i < clock_index))
        return tokens[closest]

    def _find_calendar_date(self, tokens: list[str], expression: TimeExpression) -> bool:
        """'ngày|mùng|mồng <number> [tháng <number>]' → explicit date."""
        for index, token in enumerate(tokens):
            if token not in ("ngày", "mùng", "mồng") or index + 1 >= len(tokens):
                continue
            if tokens[index + 1] in RELATIVE_DAY_WORDS or tokens[index + 1] in ("kia", "nữa"):
                continue  # "ngày mai", "ngày mốt", "ngày kia"
            day_match = longest_number_starting_at(tokens, index + 1)
            if day_match is None or not 1 <= day_match[0] <= 31:
                continue
            month = None
            if day_match[1] < len(tokens) and tokens[day_match[1]] == "tháng":
                month_match = longest_number_starting_at(tokens, day_match[1] + 1, max_length=2)
                if month_match and 1 <= month_match[0] <= 12:
                    month = month_match[0]
            expression.date_type, expression.day_of_month, expression.month = "calendar_date", day_match[0], month
            expression.matched.append(" ".join(tokens[index:day_match[1] + (2 if month else 0)]))
            return True
        return False

    def _find_relative_days(self, tokens: list[str], expression: TimeExpression) -> bool:
        """'<number> ngày|tuần nữa/tới', 'hôm nay / tối nay', 'mai', 'mốt', 'ngày kia' → offset in days."""
        for index, token in enumerate(tokens):
            if token in ("ngày", "tuần") and index + 1 < len(tokens) and tokens[index + 1] in ("nữa", "tới"):
                count = longest_number_ending_at(tokens, index)
                if count is not None:
                    days = count[0] * (7 if token == "tuần" else 1)
                    self._set_relative(expression, days, " ".join(tokens[count[1]:index + 2]))
                    return True
        for index, token in enumerate(tokens):
            previous = tokens[index - 1] if index > 0 else ""
            if token == "kia" and previous == "ngày":
                self._set_relative(expression, 2, "ngày kia")
                return True
            if token in RELATIVE_DAY_WORDS and previous not in TENS_MARKERS:  # not "hai mươi mốt"
                self._set_relative(expression, RELATIVE_DAY_WORDS[token], f"{previous} {token}".strip())
                return True
        return False

    @staticmethod
    def _set_relative(expression: TimeExpression, days: int, phrase: str) -> None:
        """Store a relative-days result."""
        expression.date_type, expression.day_offset = "relative_days", days
        expression.matched.append(phrase)

    def _find_weekday(self, tokens: list[str], expression: TimeExpression) -> bool:
        """'thứ hai..thứ bảy', 'thứ 2..7', 'chủ nhật', 'cuối tuần' + optional 'tuần sau/tới (nữa)'."""
        weekday, phrase = None, ""
        for index, token in enumerate(tokens[:-1]):
            following = tokens[index + 1]
            if token == "thứ" and following in WEEKDAY_WORDS:
                weekday, phrase = WEEKDAY_WORDS[following], f"thứ {following}"
            elif token == "thứ" and following.isdigit() and 2 <= int(following) <= 7:
                weekday, phrase = int(following) - 2, f"thứ {following}"
            elif (token, following) == ("chủ", "nhật"):
                weekday, phrase = 6, "chủ nhật"
            elif (token, following) == ("cuối", "tuần"):
                weekday, phrase = 6, "cuối tuần"
            if weekday is not None:
                break
        if weekday is None:
            return False
        expression.date_type, expression.weekday = "weekday", weekday
        expression.week_offset = self._week_offset(tokens)
        expression.matched.append(phrase)
        return True

    @staticmethod
    def _week_offset(tokens: list[str]) -> int:
        """1 for 'tuần sau' / 'tuần tới', 2 for 'tuần sau nữa', else 0."""
        text = " ".join(tokens)
        if re.search(r"\btuần (sau|tới) nữa\b", text):
            return 2
        if re.search(r"\btuần (sau|tới)\b", text):
            return 1
        return 0
