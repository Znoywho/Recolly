"""Sleep and alertness on real dates (H7, H8, S1, O1).

Each night comes from one of three sources:
- `observed`: a confirmed sleep log;
- `typical`: the questionnaire typical week. Used for every night while the user has no
  sleep log yet, and to fill past nights without a log;
- `projected`: once the user has logs, the 2PM free-runs from "now" on (fall asleep when
  H reaches H+, wake at H-), but wakes no later than the first class minus morning prep.
Process S runs a week of warm-up first, in 5-minute steps of local wall-clock time.
"""

import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from app.core.timeutil import clock_from_hours
from app.service.sleep.two_process import (
    STEP_HOURS,
    Params,
    circadian,
    kss_from_alertness,
    lower_threshold,
    step_pressure,
    upper_threshold,
)
from app.service.sleep.typical_week import WeekSchedule

STEP = timedelta(minutes=5)
DAY_STEPS = 24 * 12
WARMUP_DAYS = 7
KSS_SIGMA = 0.75                    # predictive SD around the model mean (95 % band ±1.47)
INERTIA_STEPS = 6                   # 30 min after waking: never a golden hour
MIN_WINDOW_STEPS = 6                # golden / low windows last at least 30 min
OBSERVED, PROJECTED, TYPICAL = "observed", "projected", "typical"


def alertness_score(kss: float) -> int:
    """UI number: 100 = KSS 1 (very alert), 0 = KSS 9."""
    return max(0, min(100, round(100 * (9 - kss) / 8)))


def kss_band(kss: float) -> tuple[float, float]:
    return max(1.0, kss - 1.96 * KSS_SIGMA), min(9.0, kss + 1.96 * KSS_SIGMA)


@dataclass(frozen=True)
class Point:
    time: datetime
    asleep: bool
    sleep_state: str
    process_s: float
    process_c: float
    upper_threshold: float
    lower_threshold: float
    alertness: float
    kss: float | None


@dataclass(frozen=True)
class Window:
    start: datetime
    end: datetime
    mean_kss: float


@dataclass(frozen=True)
class Episode:
    start: datetime
    end: datetime
    state: str


@dataclass(frozen=True)
class ProjectedNight:
    night_of: date
    natural_sleep_at: datetime
    natural_wake_at: datetime
    required_wake_at: datetime | None
    recommended_sleep_at: datetime
    projected_sleep_minutes: int


def _quantile(sorted_values: Sequence[float], q: float) -> float:
    pos = (len(sorted_values) - 1) * q
    low = math.floor(pos)
    high = min(low + 1, len(sorted_values) - 1)
    return sorted_values[low] + (sorted_values[high] - sorted_values[low]) * (pos - low)


class Timeline:
    """Build with `Timeline.build(...)`; times are aware datetimes in `tz`."""

    def __init__(self, tz: ZoneInfo, origin: datetime, first_index: int, last_index: int,
                 params: Params, asleep: list[bool], state: list[str], pressure: list[float],
                 sleep_need_hours: float, required_wake: Callable[[date], datetime | None]):
        self.tz = tz
        self.origin = origin
        self.first_index = first_index      # first step of the requested days
        self.last_index = last_index        # end (exclusive) of the requested days
        self.params = params
        self.asleep = asleep
        self.state = state
        self.pressure = pressure
        self.sleep_need_hours = sleep_need_hours
        self.required_wake = required_wake

    # ─────────────────────────── building ───────────────────────────

    @classmethod
    def build(cls, *, tz: ZoneInfo, first_day: date, days: int, now: datetime, params: Params,
              schedule: WeekSchedule, logs: Sequence[tuple[datetime, datetime]],
              first_class: dict[date, datetime], prep: timedelta,
              sleep_need_hours: float) -> "Timeline":
        origin = datetime.combine(first_day - timedelta(days=WARMUP_DAYS), time(0), tz)
        n = (WARMUP_DAYS + days + 1) * DAY_STEPS  # one extra day closes the last night

        def required_wake(day: date) -> datetime | None:
            first = first_class.get(day)
            return first - prep if first else None

        def index(dt: datetime) -> int:
            return math.ceil((dt - origin) / STEP)

        asleep, state = [False] * n, [TYPICAL if not logs else OBSERVED] * n
        static: list[Episode] = [Episode(s.astimezone(tz), w.astimezone(tz), OBSERVED) for s, w in logs]
        for night in cls._typical_nights(origin.date() - timedelta(days=1), n // DAY_STEPS + 2, schedule, tz):
            overlaps_log = any(e.start < night.end and night.start < e.end for e in static)
            if not logs or (night.start < now and not overlaps_log):
                static.append(night)
        for episode in static:
            for i in range(max(0, index(episode.start)), min(n, index(episode.end))):
                asleep[i] = True
                state[i] = episode.state

        dynamic_from = min(n, max(0, index(now))) if logs else n
        pressure = [0.0] * n
        h, sleeping, slept_since = 0.5, False, now
        for i in range(n):
            t = i * STEP_HOURS
            if i == dynamic_from:
                sleeping = asleep[i]
            if i >= dynamic_from:
                moment = origin + i * STEP
                if sleeping:
                    alarm = required_wake(moment.date())
                    if h <= lower_threshold(t, params) or (alarm and slept_since < alarm <= moment):
                        sleeping = False
                elif h >= upper_threshold(t, params):
                    sleeping, slept_since = True, moment
                asleep[i], state[i] = sleeping, PROJECTED
            pressure[i] = h
            h = step_pressure(h, asleep[i], params)

        first_index = WARMUP_DAYS * DAY_STEPS
        return cls(tz, origin, first_index, first_index + days * DAY_STEPS, params, asleep, state,
                   pressure, sleep_need_hours, required_wake)

    @staticmethod
    def _typical_nights(first: date, count: int, schedule: WeekSchedule, tz: ZoneInfo) -> list[Episode]:
        """The typical-week sleep that ends on the morning of each day."""
        nights = []
        for offset in range(count):
            day = first + timedelta(days=offset)
            onset, wake = schedule.night_ending_on(day.weekday())
            start_day = day - timedelta(days=1) if onset > 12 else day
            nights.append(Episode(datetime.combine(start_day, clock_from_hours(onset), tz),
                                  datetime.combine(day, clock_from_hours(wake), tz), TYPICAL))
        return nights

    # ─────────────────────────── reading ───────────────────────────

    def time_at(self, i: int) -> datetime:
        return self.origin + i * STEP

    def index(self, dt: datetime) -> int:
        """Step that contains `dt`."""
        return math.floor((dt.astimezone(self.tz) - self.origin) / STEP)

    def point(self, i: int) -> Point:
        t = i * STEP_HOURS
        upper = upper_threshold(t, self.params)
        alert = upper - self.pressure[i]
        return Point(
            time=self.time_at(i),
            asleep=self.asleep[i],
            sleep_state=self.state[i],
            process_s=self.pressure[i],
            process_c=circadian(t, self.params),
            upper_threshold=upper,
            lower_threshold=lower_threshold(t, self.params),
            alertness=alert,
            kss=None if self.asleep[i] else kss_from_alertness(alert),
        )

    def at(self, dt: datetime) -> Point:
        return self.point(min(max(self.index(dt), 0), len(self.asleep) - 1))

    def points(self, interval_minutes: int) -> list[Point]:
        stride = interval_minutes // 5
        return [self.point(i) for i in range(self.first_index, self.last_index, stride)]

    def kss(self, i: int) -> float | None:
        return self.point(i).kss

    def episodes(self, start: datetime | None = None, end: datetime | None = None) -> list[Episode]:
        """Sleep runs overlapping [start, end) (default: the requested days)."""
        lo = self.first_index if start is None else max(0, self.index(start))
        hi = self.last_index if end is None else min(len(self.asleep), self.index(end) + 1)
        # Extend to whole runs that cross the edges.
        while lo > 0 and self.asleep[lo] and self.asleep[lo - 1]:
            lo -= 1
        while hi < len(self.asleep) and self.asleep[hi - 1] and self.asleep[hi]:
            hi += 1
        runs, begin = [], None
        for i in range(lo, hi):
            if self.asleep[i] and begin is None:
                begin = i
            elif not self.asleep[i] and begin is not None:
                runs.append(Episode(self.time_at(begin), self.time_at(i), self.state[begin]))
                begin = None
        if begin is not None:
            runs.append(Episode(self.time_at(begin), self.time_at(hi), self.state[begin]))
        return runs

    def _steps_since_wake(self, i: int) -> int:
        steps = 0
        while i - steps - 1 >= 0 and not self.asleep[i - steps - 1] and steps <= INERTIA_STEPS:
            steps += 1
        return steps if i - steps - 1 >= 0 else INERTIA_STEPS + 1

    def windows(self, day: date) -> tuple[list[Window], list[Window]]:
        """(golden hours, low windows) of one day, from that day's awake KSS quartiles."""
        start = self.index(datetime.combine(day, time(0), self.tz))
        awake = [(i, self.kss(i)) for i in range(start, start + DAY_STEPS) if not self.asleep[i]]
        if not awake:
            return [], []
        values = sorted(k for _, k in awake)
        p25, p75 = _quantile(values, 0.25), _quantile(values, 0.75)
        peaks = self._runs(awake, lambda i, k: k <= p25 and self._steps_since_wake(i) >= INERTIA_STEPS)
        lows = self._runs(awake, lambda i, k: k >= p75)
        return peaks, lows

    def _runs(self, awake: list[tuple[int, float]], keep: Callable[[int, float], bool]) -> list[Window]:
        windows, run = [], []
        for i, k in awake + [(-1, 0.0)]:
            if i >= 0 and keep(i, k) and (not run or run[-1][0] == i - 1):
                run.append((i, k))
                continue
            if len(run) >= MIN_WINDOW_STEPS:
                windows.append(Window(self.time_at(run[0][0]), self.time_at(run[-1][0] + 1),
                                      sum(k for _, k in run) / len(run)))
            run = [(i, k)] if i >= 0 and keep(i, k) else []
        return windows

    def night(self, night_of: date) -> ProjectedNight:
        """Model sleep window of one night plus the recommended bedtime (H8 projected_sleep)."""
        noon = self.index(datetime.combine(night_of, time(12), self.tz))
        h, i = self.pressure[noon], noon
        while i < noon + DAY_STEPS and h < upper_threshold(i * STEP_HOURS, self.params):
            h, i = step_pressure(h, False, self.params), i + 1
        natural_sleep = i
        while i < natural_sleep + 16 * 12 and h > lower_threshold(i * STEP_HOURS, self.params):
            h, i = step_pressure(h, True, self.params), i + 1
        natural_sleep_at, natural_wake_at = self.time_at(natural_sleep), self.time_at(i)

        required = self.required_wake(night_of + timedelta(days=1))
        recommended = natural_sleep_at
        if required is not None:
            recommended = min(natural_sleep_at, required - timedelta(hours=self.sleep_need_hours))
        night_runs = self.episodes(self.time_at(noon), self.time_at(noon + DAY_STEPS))
        longest = max((e.end - e.start for e in night_runs), default=timedelta(0))
        return ProjectedNight(night_of, natural_sleep_at, natural_wake_at, required, recommended,
                              int(longest.total_seconds() // 60))
