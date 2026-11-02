"""Timezone helpers and the contract's `HH:MM` ClockTime type."""

import re
from datetime import UTC, date, datetime, time, timedelta
from typing import Annotated
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BeforeValidator, PlainSerializer, WithJsonSchema

CLOCK_PATTERN = r"^([01][0-9]|2[0-3]):[0-5][0-9]$"
_CLOCK = re.compile(CLOCK_PATTERN)


def _parse_clock(value: object) -> object:
    if isinstance(value, str):
        if not _CLOCK.match(value):
            raise ValueError("must be HH:MM (24h)")
        hour, minute = value.split(":")
        return time(int(hour), int(minute))
    return value  # datetime.time from the ORM


ClockTime = Annotated[
    time,
    BeforeValidator(_parse_clock),
    PlainSerializer(lambda t: t.strftime("%H:%M"), return_type=str, when_used="json"),
    WithJsonSchema({"type": "string", "pattern": CLOCK_PATTERN, "examples": ["23:30"]}),
]


def now_utc() -> datetime:
    return datetime.now(UTC)


def is_valid_timezone(name: str) -> bool:
    try:
        ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return False
    return True


def today(tz: ZoneInfo) -> date:
    return datetime.now(tz).date()


def at(day: date, clock: time, tz: ZoneInfo) -> datetime:
    return datetime.combine(day, clock, tz)


def day_start(day: date, tz: ZoneInfo) -> datetime:
    return datetime.combine(day, time(0), tz)


def hours(clock: time) -> float:
    """07:30 -> 7.5"""
    return clock.hour + clock.minute / 60


def clock_from_hours(value: float) -> time:
    """7.5 -> 07:30 (wraps around midnight, rounded to the minute)."""
    minutes = round(value * 60) % (24 * 60)
    return time(minutes // 60, minutes % 60)


def floor_to(dt: datetime, minutes: int) -> datetime:
    return dt - timedelta(minutes=dt.minute % minutes, seconds=dt.second, microseconds=dt.microsecond)
