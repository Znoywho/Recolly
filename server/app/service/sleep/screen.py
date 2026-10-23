"""Guess last night's sleep from Android screen on/off events.

Rule: the longest screen-off gap of each night (noon to noon) that lasts at least
MIN_SLEEP_HOURS is the main sleep. Waking up to check the phone splits the gap, so
the result is only a suggestion: the user confirms or edits it on the morning card.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from app.service.sleep.chronotype import Night

MIN_SLEEP_HOURS = 3.0


@dataclass(frozen=True)
class ScreenEvent:
    at: datetime
    on: bool


@dataclass(frozen=True)
class SleepGuess:
    night: date   # the evening the night starts on
    start: datetime
    end: datetime

    def to_night(self) -> Night:
        return Night(self.start.hour + self.start.minute / 60, self.end.hour + self.end.minute / 60)


def guess_sleep(events: Sequence[ScreenEvent]) -> list[SleepGuess]:
    """One guess per night that has a long enough screen-off gap."""
    events = sorted(events, key=lambda e: e.at)
    best: dict[date, SleepGuess] = {}
    for prev, nxt in zip(events, events[1:]):
        if prev.on or not nxt.on:
            continue  # only "off -> next on" gaps
        if nxt.at - prev.at < timedelta(hours=MIN_SLEEP_HOURS):
            continue
        night = (prev.at - timedelta(hours=12)).date()
        current = best.get(night)
        if current is None or nxt.at - prev.at > current.end - current.start:
            best[night] = SleepGuess(night, prev.at, nxt.at)
    return [best[n] for n in sorted(best)]
