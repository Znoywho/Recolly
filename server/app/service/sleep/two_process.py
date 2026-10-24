"""Borbély two-process model (2PM) of sleep regulation.

Process S (sleep pressure H) rises while awake and decays while asleep:
    awake:  dH/dt = (mu - H) / chi_w
    asleep: dH/dt = -H / chi_s
Process C is a 24 h cosine peaking at phase `phi`; it modulates two thresholds:
    upper H+(t) = h0_upper + amplitude * C(t)   (awake and H reaches it -> fall asleep)
    lower H-(t) = h0_lower + amplitude * C(t)   (asleep and H reaches it -> wake up)

Equations and default parameters: Skeldon & Dijk (2025), Fig. 1 and Methods.
The chronotype *is* the phase `phi`.

Time is in hours; t = 0 is 00:00 (Monday) of the first simulated day.
"""

import math
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache

STEP_HOURS = 5 / 60

# Linear link between model alertness and the Karolinska Sleepiness Scale (1 alert .. 9 fighting sleep).
# Team assumption, not from the literature.
KSS_INTERCEPT = 7.5
KSS_SLOPE = 9.0


@dataclass(frozen=True)
class Params:
    chi_s: float = 4.2       # time constant while asleep (h)
    chi_w: float = 18.2      # time constant while awake (h)
    mu: float = 1.0          # upper asymptote of sleep pressure
    h0_upper: float = 0.67   # mean upper threshold
    h0_lower: float = 0.17   # mean lower threshold
    amplitude: float = 0.12  # circadian amplitude
    period: float = 24.0
    phi: float = 16.0        # clock hour at which C(t) peaks


def circadian(t: float, p: Params) -> float:
    return math.cos(2 * math.pi * (t - p.phi) / p.period)


def upper_threshold(t: float, p: Params) -> float:
    return p.h0_upper + p.amplitude * circadian(t, p)


def lower_threshold(t: float, p: Params) -> float:
    return p.h0_lower + p.amplitude * circadian(t, p)


def step_pressure(h: float, asleep: bool, p: Params, dt: float = STEP_HOURS) -> float:
    """Exact solution of Process S over one step."""
    if asleep:
        return h * math.exp(-dt / p.chi_s)
    return p.mu + (h - p.mu) * math.exp(-dt / p.chi_w)


def simulate_forced(asleep: Sequence[bool], p: Params, dt: float = STEP_HOURS,
                    h_init: float = 0.5) -> list[float]:
    """Process S for a known sleep/wake schedule (one value per step, at the start of the step)."""
    pressure = []
    h = h_init
    for s in asleep:
        pressure.append(h)
        h = step_pressure(h, s, p, dt)
    return pressure


def simulate_free(p: Params, days: int = 20, dt: float = STEP_HOURS,
                  h_init: float = 0.5) -> list[bool]:
    """Sleep/wake decided only by the two thresholds (no alarm, no timetable)."""
    asleep = []
    h, s = h_init, False
    for i in range(round(days * 24 / dt)):
        t = i * dt
        asleep.append(s)
        if not s and h >= upper_threshold(t, p):
            s = True
        elif s and h <= lower_threshold(t, p):
            s = False
        h = step_pressure(h, s, p, dt)
    return asleep


def alertness(t: float, h: float, p: Params) -> float:
    """Distance to the sleep threshold. A <= 0 means the model says the person should be asleep."""
    return upper_threshold(t, p) - h


def kss_from_alertness(a: float) -> float:
    return KSS_INTERCEPT - KSS_SLOPE * a


def circular_mean_hours(hours: Sequence[float], weights: Sequence[float] | None = None) -> float:
    if weights is None:
        weights = [1.0] * len(hours)
    angles = [h * 2 * math.pi / 24 for h in hours]
    sin = sum(w * math.sin(a) for w, a in zip(weights, angles))
    cos = sum(w * math.cos(a) for w, a in zip(weights, angles))
    return (math.atan2(sin, cos) * 24 / (2 * math.pi)) % 24


@lru_cache
def mid_sleep_offset(p: Params = Params(), dt: float = STEP_HOURS) -> float:
    """phi minus the mean mid-sleep of free-running sleep.

    The 2PM is invariant to a time shift: moving phi moves sleep by the same amount,
    so this offset is a constant (about 12.4 h with the default parameters).
    """
    asleep = simulate_free(p, days=20, dt=dt)
    mids = []
    start = None
    for i in range(1, len(asleep)):
        if asleep[i] and not asleep[i - 1]:
            start = i
        elif not asleep[i] and asleep[i - 1] and start is not None and start * dt >= 10 * 24:
            mids.append(((start + i) / 2 * dt) % 24)
    return (p.phi - circular_mean_hours(mids)) % 24


def phi_from_mid_sleep(mid_sleep: float, p: Params = Params()) -> float:
    """Convert a mid-sleep clock time (e.g. MSFsc) to the model phase phi."""
    return (mid_sleep + mid_sleep_offset(p)) % 24
