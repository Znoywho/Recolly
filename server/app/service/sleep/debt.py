"""Sleep need and sleep debt over the last week.

Sleep need is the value the user typed (`sleep_need_hours`, default 8.0 h), kept within
MIN_NEED_HOURS..MAX_NEED_HOURS: adults need at least 7 h (Watson et al. 2015), whatever they believe.
Free-day sleep from the quiz is not used as the need: 18-24 year olds catch up ~0.71 h on free days
(NHANES 2017-2020), so it would invent ~3.5 h of debt per week (docs/sleep-model.md section 6).

Debt is plain arithmetic (need - slept, summed over the last nights), not the 2PM,
because the 2PM under-estimates chronic sleep restriction. Extra sleep on any night
in the window counts against the debt, and the total never goes below zero
(`total_debt_minutes = max(0, Σ debt_minutes)` in docs/openapi.yaml).
"""

from collections.abc import Sequence
from dataclasses import dataclass

from app.service.sleep.chronotype import Night

MIN_NEED_HOURS = 7.0
MAX_NEED_HOURS = 10.0
DEFAULT_NEED_HOURS = 8.0
WINDOW_NIGHTS = 7


@dataclass(frozen=True)
class SleepDebt:
    need_hours: float
    nights: int
    average_sleep_hours: float | None
    debt_hours: float
    per_night: list[float]   # need - slept for each night, oldest first (negative = extra sleep)


def sleep_need(user_hours: float | None = None) -> float:
    """The user's sleep need in hours (default 8.0), clamped to 7-10 h."""
    need = DEFAULT_NEED_HOURS if user_hours is None else user_hours
    return min(MAX_NEED_HOURS, max(MIN_NEED_HOURS, need))


def sleep_debt(nights: Sequence[Night], need_hours: float) -> SleepDebt:
    """`nights` oldest first; only the last WINDOW_NIGHTS are counted."""
    recent = list(nights)[-WINDOW_NIGHTS:]
    per_night = [need_hours - n.duration for n in recent]
    return SleepDebt(
        need_hours=need_hours,
        nights=len(recent),
        average_sleep_hours=sum(n.duration for n in recent) / len(recent) if recent else None,
        debt_hours=max(0.0, sum(per_night)),
        per_night=per_night,
    )
