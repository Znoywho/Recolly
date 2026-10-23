"""Chronotype: lion / bear / wolf from the mid-point of free-day sleep.

1. Onboarding asks two questions: on a free day without an alarm, when do you fall
   asleep and when do you wake up? Their mid-point gives a first guess.
2. Every confirmed free-day night (screen-inferred or typed in) pulls the estimate
   towards the user's real sleep. The quiz counts as PRIOR_NIGHTS nights, so after
   about a week the real data outweighs it.

The animals are a display layer only; the 2PM uses the phase `phi` as a number.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum

from app.service.sleep.two_process import circular_mean_hours, phi_from_mid_sleep

# Cut-offs on free-day mid-sleep, placed around the assumed student mean (~05:00).
# Provisional: re-fit on real students.
LION_BEFORE_MID_SLEEP = 4.0
WOLF_FROM_MID_SLEEP = 6.0

PRIOR_NIGHTS = 7


class Animal(StrEnum):
    LION = "lion"
    BEAR = "bear"
    WOLF = "wolf"


@dataclass(frozen=True)
class Night:
    """Clock hours as floats, e.g. 23.5 = 23:30, 0.75 = 00:45."""

    onset: float
    wake: float

    @property
    def duration(self) -> float:
        return (self.wake - self.onset) % 24

    @property
    def mid_sleep(self) -> float:
        return (self.onset + self.duration / 2) % 24


@dataclass(frozen=True)
class Chronotype:
    animal: Animal
    mid_sleep: float   # clock hour
    phi_hours: float   # 2PM circadian phase
    nights_used: int   # real nights behind the estimate (0 = quiz only)


def animal_from_mid_sleep(mid_sleep: float) -> Animal:
    h = mid_sleep - 24 if mid_sleep > 12 else mid_sleep  # 23:30 -> -0.5
    if h < LION_BEFORE_MID_SLEEP:
        return Animal.LION
    if h >= WOLF_FROM_MID_SLEEP:
        return Animal.WOLF
    return Animal.BEAR


def estimate(quiz: Night, free_nights: Sequence[Night] = ()) -> Chronotype:
    """Blend the quiz answer with real free-day nights (no alarm the next morning)."""
    mids = [quiz.mid_sleep] + [n.mid_sleep for n in free_nights]
    weights = [PRIOR_NIGHTS] + [1] * len(free_nights)
    mid = circular_mean_hours(mids, weights)
    return Chronotype(
        animal=animal_from_mid_sleep(mid),
        mid_sleep=mid,
        phi_hours=phi_from_mid_sleep(mid),
        nights_used=len(free_nights),
    )
