"""Typical week: the questionnaire sleep times run through the 2PM.

The night before a school day uses the school-day sleep times, every other night the
free-day times (MCTQ convention). Three weeks are simulated so Process S settles; the
last week is reported. Only questionnaire data is needed (docs/research/TRIEN_KHAI.md §3.2).

The 2PM has no sleep inertia and under-estimates chronic sleep restriction
(Van Dongen et al. 2007, Discussion): the first 30 min after waking are excluded
from peak blocks, and the weekly sleep-debt trend is a lower bound.
"""

import math
from dataclasses import dataclass, replace

from app.service.sleep.chronotype import MctqAnswers
from app.service.sleep.two_process import (
    STEP_HOURS,
    Params,
    alertness,
    circadian,
    kss_from_alertness,
    simulate_forced,
)

STEP_MINUTES = round(STEP_HOURS * 60)
DAY_STEPS = 24 * 60 // STEP_MINUTES
WARMUP_WEEKS = 2
WAKE_BUFFER_HOURS = 0.5
BED_BUFFER_HOURS = 1.0
PEAK_BLOCK_HOURS = 1.5
REPORT_HOURS = (8, 14, 22)


@dataclass(frozen=True)
class WeekSchedule:
    school_sleep: tuple[float, float]       # (sleep onset, wake) clock hours
    free_sleep: tuple[float, float]
    school_days: frozenset[int] = frozenset(range(5))  # 0 = Monday

    def shift_school_onset(self, hours: float) -> "WeekSchedule":
        """What-if: go to sleep `hours` later (negative = earlier) before school days."""
        onset, wake = self.school_sleep
        return replace(self, school_sleep=((onset + hours) % 24, wake))


@dataclass(frozen=True)
class WeekPoint:
    day: int            # 0 = Monday
    hour: float         # clock hour
    asleep: bool
    process_s: float
    process_c: float
    alertness: float
    kss: float | None   # None while asleep


@dataclass(frozen=True)
class DaySummary:
    day: int
    wake_hour: float
    sleep_hour: float                  # clock hour of the next sleep onset (may be after midnight)
    kss_at: dict[int, float | None]    # REPORT_HOURS -> predicted KSS, None if asleep
    worst_hour: float
    worst_kss: float
    minutes_past_threshold: int        # awake while alertness <= 0 ("should be asleep")
    peak_start_hour: float | None      # best PEAK_BLOCK_HOURS block, outside the wake/bed buffers
    peak_mean_kss: float | None


@dataclass(frozen=True)
class TypicalWeek:
    phi_hours: float
    points: list[WeekPoint]                   # 7 days, one per STEP_MINUTES
    sleep_episodes: list[tuple[float, float]]  # hours since Monday 00:00 of the reported week
    days: list[DaySummary]


def schedule_from_mctq(a: MctqAnswers, school_days: frozenset[int] | None = None) -> WeekSchedule:
    school = (a.sleep_onset_work, a.sleep_end_work)
    free = (a.sleep_onset_free, a.sleep_end_free)
    if a.work_days == 0:
        school = free
    elif a.work_days == 7:
        free = school
    if school_days is None:
        school_days = frozenset(range(a.work_days))
    return WeekSchedule(school, free, school_days)


def _step_at(hours: float) -> int:
    """First step index at or after `hours` (rounded to whole minutes to avoid float drift)."""
    return math.ceil(round(hours * 60) / STEP_MINUTES)


def sleep_mask(schedule: WeekSchedule, days: int) -> list[bool]:
    n = days * DAY_STEPS
    mask = [False] * n
    for d in range(days + 1):
        onset, wake = (schedule.school_sleep if d % 7 in schedule.school_days
                       else schedule.free_sleep)
        # The sleep that ends on the morning of day d starts the evening before (or after midnight).
        start = d * 24 + (onset - 24 if onset > 12 else onset)
        end = d * 24 + wake
        for i in range(max(0, _step_at(start)), min(n, _step_at(end))):
            mask[i] = True
    return mask


def _runs(mask: list[bool], value: bool) -> list[tuple[int, int]]:
    """Maximal [start, end) index ranges where mask == value."""
    runs, start = [], None
    for i, m in enumerate(mask):
        if m == value and start is None:
            start = i
        elif m != value and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, len(mask)))
    return runs


def _summarise_day(day: int, s: int, e: int, offset: int, mask: list[bool],
                   alert: list[float], kss: list[float]) -> DaySummary:
    awake = range(s, e)
    worst = max(awake, key=lambda i: kss[i])
    block = round(PEAK_BLOCK_HOURS * 60) // STEP_MINUTES
    first = s + round(WAKE_BUFFER_HOURS * 60) // STEP_MINUTES
    last = e - round(BED_BUFFER_HOURS * 60) // STEP_MINUTES - block
    peak, peak_kss = None, None
    for j in range(first, last + 1):
        mean = sum(kss[j:j + block]) / block
        if peak_kss is None or mean < peak_kss:
            peak, peak_kss = j, mean
    base = offset + day * DAY_STEPS
    kss_at = {}
    for h in REPORT_HOURS:
        i = base + h * 60 // STEP_MINUTES
        kss_at[h] = None if mask[i] else kss[i]

    def clock(i: int) -> float:
        return (i * STEP_HOURS) % 24

    return DaySummary(
        day=day,
        wake_hour=clock(s),
        sleep_hour=clock(e),
        kss_at=kss_at,
        worst_hour=clock(worst),
        worst_kss=kss[worst],
        minutes_past_threshold=sum(STEP_MINUTES for i in awake if alert[i] <= 0),
        peak_start_hour=None if peak is None else clock(peak),
        peak_mean_kss=peak_kss,
    )


def simulate_typical_week(schedule: WeekSchedule, phi: float,
                          params: Params = Params()) -> TypicalWeek:
    p = replace(params, phi=phi)
    days = 7 * (WARMUP_WEEKS + 1) + 1  # one extra day closes Sunday's waking period
    mask = sleep_mask(schedule, days)
    pressure = simulate_forced(mask, p)
    t = [i * STEP_HOURS for i in range(len(mask))]
    alert = [alertness(t[i], pressure[i], p) for i in range(len(mask))]
    kss = [kss_from_alertness(a) for a in alert]

    offset = 7 * WARMUP_WEEKS * DAY_STEPS
    week_end = offset + 7 * DAY_STEPS
    points = [
        WeekPoint(day=(i - offset) // DAY_STEPS, hour=t[i] % 24, asleep=mask[i],
                  process_s=pressure[i], process_c=circadian(t[i], p), alertness=alert[i],
                  kss=None if mask[i] else kss[i])
        for i in range(offset, week_end)
    ]
    episodes = [((s - offset) * STEP_HOURS, (e - offset) * STEP_HOURS)
                for s, e in _runs(mask, True) if offset <= s < week_end]
    summaries = [
        _summarise_day((s - offset) // DAY_STEPS, s, e, offset, mask, alert, kss)
        for s, e in _runs(mask, False)
        if offset <= s < week_end and e < len(mask)
    ]
    return TypicalWeek(phi, points, episodes, summaries)
