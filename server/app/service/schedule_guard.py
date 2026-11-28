"""Time clashes: when an event is saved (in the app or pulled from Google), find what it overlaps,
and let movable CP-SAT blocks make room instead of keeping two things at the same time.

Fixed: classes, manual events, a todo's fixed slot, anything from Google, Google busy times.
Movable: study and rest blocks the scheduler placed (`source = scheduler`).
Fixed vs fixed is only reported (`clashes` in the API answer); the user decides.
"""

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.core.timeutil import now_utc, today
from app.models.enums import EventKind, EventSource
from app.models.event import Event
from app.models.user import User
from app.repository.event_repository import EventRepository
from app.schemas.schedule import ScheduleOptions
from app.service import biorhythm_service, scheduler
from app.service.event_service import forget_google_copy, initial_sync_status, occurrences

CHECK_DAYS = 14  # a recurring event is checked over its next two weeks
REPLAN_DAYS = scheduler.MAX_DAYS - 1  # moved blocks are re-planned over the longest range CP-SAT allows


@dataclass(frozen=True)
class Busy:
    """A busy time on the user's own Google calendar (read for this request, never stored)."""

    start: datetime
    end: datetime
    title: str


@dataclass(frozen=True)
class Clash:
    title: str
    start_at: datetime
    end_at: datetime
    event_id: uuid.UUID | None  # None for a Google busy time
    kind: EventKind | None
    source: str  # "recolly" | "google"
    movable: bool


def is_movable(event: Event) -> bool:
    """Only blocks CP-SAT placed may be moved without asking."""
    return event.source is EventSource.SCHEDULER and event.kind in (EventKind.STUDY, EventKind.REST)


def check_range(event: Event, now: datetime) -> tuple[datetime, datetime]:
    """Where to look for clashes: the event itself, or the next CHECK_DAYS of a series."""
    if not event.rrule:
        return event.start_at, event.end_at
    start = max(event.start_at, now)
    return start, start + timedelta(days=CHECK_DAYS)


def find_clashes(db: Session, user: User, event: Event, busy: list[Busy]) -> list[Clash]:
    """Everything overlapping `event` (all-day events never clash), earliest first."""
    if event.all_day:
        return []
    tz = ZoneInfo(user.timezone)
    start, end = check_range(event, now_utc())
    mine = occurrences([event], start, end, tz)

    def overlaps(a_start: datetime, a_end: datetime) -> bool:
        return any(a_start < m.end and m.start < a_end for m in mine)

    others = [e for e in EventRepository(db).list_candidates(user.id, start, end) if e.id != event.id]
    clashes = [Clash(o.event.title, o.start, o.end, o.event.id, o.event.kind, "recolly", is_movable(o.event))
               for o in occurrences(others, start, end, tz)
               if not o.event.all_day and overlaps(o.start, o.end)]
    clashes += [Clash(b.title, b.start, b.end, None, None, "google", False) for b in busy if overlaps(b.start, b.end)]
    return sorted(clashes, key=lambda c: c.start_at)


def move_blocks(db: Session, user: User, clashes: list[Clash],
                busy: list[Busy]) -> tuple[set[uuid.UUID], list[Event]]:
    """Delete the future movable blocks among `clashes` and re-plan their todos' lost minutes
    with CP-SAT (default options, next REPLAN_DAYS days). Returns (deleted ids, new blocks).

    Without a sleep profile CP-SAT cannot run: the blocks stay and remain reported as clashes.
    """
    now = now_utc()
    ids = {c.event_id for c in clashes if c.movable and c.start_at > now}
    profile = user.health_profile
    if not ids or profile is None:
        return set(), []
    blocks = [db.get(Event, event_id) for event_id in ids]
    todo_ids = {b.todo_id for b in blocks if b.todo_id and b.kind is EventKind.STUDY}
    for block in blocks:
        forget_google_copy(db, user, block)
        db.delete(block)
    db.flush()
    if not todo_ids:
        return ids, []
    first = today(ZoneInfo(user.timezone))
    timeline = biorhythm_service.timeline_for(db, user, profile, first, REPLAN_DAYS)
    result = scheduler.generate(db, user, timeline, first, first + timedelta(days=REPLAN_DAYS - 1), list(todo_ids),
                                ScheduleOptions(include_bedtime_blocks=False), now, busy)
    moved = [Event(user_id=user.id, title=b["title"], start_at=b["start_at"], end_at=b["end_at"],
                   kind=EventKind.STUDY, source=EventSource.SCHEDULER, todo_id=b["todo_id"],
                   sync_status=initial_sync_status(user))
             for b in result["blocks"] if b["kind"] == "study"]
    db.add_all(moved)
    db.flush()
    return ids, moved


def make_room(db: Session, user: User, events: list[Event], busy: list[Busy]) -> list[Event]:
    """`guard` for many saved events at once (a pull): one CP-SAT run for every block they overlap."""
    movable = {c.event_id: c for event in events if not is_movable(event)
               for c in find_clashes(db, user, event, busy) if c.movable}
    return move_blocks(db, user, list(movable.values()), busy)[1]


def guard(db: Session, user: User, event: Event, busy: list[Busy]) -> tuple[list[Clash], list[Event]]:
    """After `event` was saved: move the CP-SAT blocks it overlaps; returns (clashes left, moved blocks).

    A movable block that was itself moved only reports its clashes (it never pushes other blocks).
    """
    clashes = find_clashes(db, user, event, busy)
    if is_movable(event):
        return clashes, []
    deleted, moved = move_blocks(db, user, clashes, busy)
    return [c for c in clashes if c.event_id not in deleted], moved
