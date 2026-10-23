"""Energy curve for one day: a usual sleep schedule run through the 2PM.

The same night is repeated for a week so Process S settles, then the last day is
reported as KSS every 5 minutes (1 alert .. 9 fighting sleep).

The 2PM has no sleep inertia, so it says you are most alert right after waking:
the first 30 min after waking and the last hour before bed are never picked as a peak.
"""

import math
from dataclasses import dataclass, replace

from app.service.sleep.chronotype import Night
from app.service.sleep.two_process import STEP_HOURS, Params, alertness, kss_from_alertness, simulate_forced

STEP_MINUTES = round(STEP_HOURS * 60)
DAY_STEPS = 24 * 60 // STEP_MINUTES
WARMUP_DAYS = 7
WAKE_BUFFER_HOURS = 0.5
BED_BUFFER_HOURS = 1.0
PEAK_BLOCK_HOURS = 1.5


@dataclass(frozen=True)
class EnergyPoint:
    hour: float         # clock hour
    kss: float | None   # None while asleep
    study_ok: bool      # awake and outside the wake/bed buffers


@dataclass(frozen=True)
class DayEnergy:
    points: list[EnergyPoint]   # DAY_STEPS points from 00:00
    peak_start_hour: float | None
    minutes_past_threshold: int  # awake while the model says "should be asleep"


def _step_at(hours: float) -> int:
    """First step at or after `hours` (rounded to whole minutes to avoid float drift)."""
    return math.ceil(round(hours * 60) / STEP_MINUTES)


def _mask(night: Night, days: int) -> list[bool]:
    """Sleep mask; every night ends at `wake` on the morning of day d."""
    n = days * DAY_STEPS
    mask = [False] * n
    onset = night.onset % 24
    for d in range(days + 1):
        start = d * 24 + (onset - 24 if onset > 12 else onset)
        end = d * 24 + night.wake
        for i in range(max(0, _step_at(start)), min(n, _step_at(end))):
            mask[i] = True
    return mask


def day_energy(night: Night, phi: float, params: Params = Params()) -> DayEnergy:
    p = replace(params, phi=phi)
    days = WARMUP_DAYS + 1
    asleep = _mask(night, days)
    pressure = simulate_forced(asleep, p)
    offset = WARMUP_DAYS * DAY_STEPS

    # Buffers around the sleep on either side of the reported day.
    near = _mask(Night(night.onset - BED_BUFFER_HOURS, night.wake + WAKE_BUFFER_HOURS), days)

    points, alert = [], []
    for i in range(offset, offset + DAY_STEPS):
        t = i * STEP_HOURS
        a = alertness(t, pressure[i], p)
        alert.append(None if asleep[i] else a)
        points.append(EnergyPoint(hour=t % 24, kss=None if asleep[i] else kss_from_alertness(a),
                                  study_ok=not near[i]))

    block = round(PEAK_BLOCK_HOURS * 60) // STEP_MINUTES
    peak, peak_kss = None, None
    for j in range(DAY_STEPS - block + 1):
        window = points[j:j + block]
        if all(pt.study_ok for pt in window):
            mean = sum(pt.kss for pt in window) / block
            if peak_kss is None or mean < peak_kss:
                peak, peak_kss = j, mean

    return DayEnergy(
        points=points,
        peak_start_hour=None if peak is None else points[peak].hour,
        minutes_past_threshold=sum(STEP_MINUTES for a in alert if a is not None and a <= 0),
    )
