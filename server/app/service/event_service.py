"""Event rules shared by events, timetable and scheduler: recurrence, sync status, class events."""

import re
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from dateutil.rrule import rrule, rrulestr
from sqlalchemy.orm import Session

from app.models.calendar import CalendarDeletion
from app.models.enums import EventKind, EventSource, SyncStatus, TodoStatus
from app.models.event import Event
from app.models.timetable import Subject
from app.models.todo import Todo
from app.models.user import User

BYDAY = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")
_UNTIL = re.compile(r"UNTIL=(\d{8})(?:T(\d{6}))?(Z?)", re.IGNORECASE)


def normalize_rrule(rule: str, tz: ZoneInfo) -> str:
    """Strip "RRULE:" and write UNTIL in UTC, as RFC 5545 requires for a zoned DTSTART.

    A floating UNTIL (no "Z", e.g. from Google all-day series) is read in the user's timezone;
    a date-only UNTIL means the end of that day.
    """
    rule = rule.strip()
    if rule.upper().startswith("RRULE:"):
        rule = rule[6:]

    def to_utc(match: re.Match) -> str:
        if match.group(3):
            return match.group(0)
        local = datetime.strptime(match.group(1) + (match.group(2) or "235959"), "%Y%m%d%H%M%S")
        return f"UNTIL={local.replace(tzinfo=tz).astimezone(UTC):%Y%m%dT%H%M%SZ}"

    return _UNTIL.sub(to_utc, rule)


def parse_rrule(rule: str, dtstart: datetime, tz: ZoneInfo) -> rrule:
    """dateutil rule anchored at `dtstart` in the user's timezone. ValueError if invalid."""
    parsed = rrulestr(normalize_rrule(rule, tz), dtstart=dtstart.astimezone(tz))
    if not isinstance(parsed, rrule):
        raise ValueError("only a single RRULE is supported")
    return parsed


@dataclass(frozen=True)
class Occurrence:
    event: Event
    start: datetime
    end: datetime
    recurring: bool


def occurrences(events: Iterable[Event], start: datetime, end: datetime,
                tz: ZoneInfo) -> list[Occurrence]:
    """Instances of `events` overlapping [start, end), sorted by start."""
    result = []
    for event in events:
        duration = event.end_at - event.start_at
        if not event.rrule:
            if event.start_at < end and event.end_at > start:
                result.append(Occurrence(event, event.start_at, event.end_at, False))
            continue
        try:
            rule = parse_rrule(event.rrule, event.start_at, tz)
        except ValueError:
            continue  # a rule pulled from Google that dateutil cannot read
        changed_on_google = {exception.original_start for exception in event.exceptions}
        for occ in rule.between(start.astimezone(tz) - duration, end.astimezone(tz), inc=True):
            if occ < end and occ + duration > start and occ not in changed_on_google:
                result.append(Occurrence(event, occ, occ + duration, True))
    result.sort(key=lambda o: o.start)
    return result


def initial_sync_status(user: User) -> SyncStatus:
    return SyncStatus.PENDING if user.calendar_connection is not None else SyncStatus.NOT_SYNCED


def mark_changed(event: Event, user: User) -> None:
    """A local edit is pushed on the next sync (E4: a synced event becomes `pending`)."""
    if user.calendar_connection is not None:
        event.sync_status = SyncStatus.PENDING


def forget_google_copy(db: Session, user: User, event: Event) -> None:
    """Call before deleting an event: its Google copy is deleted on the next sync."""
    conn = user.calendar_connection
    if conn is not None and event.google_event_id:
        db.add(CalendarDeletion(user_id=user.id, calendar_id=conn.calendar_id,
                                google_event_id=event.google_event_id))


def first_class_day(subject: Subject) -> date:
    return subject.start_date + timedelta(days=(subject.day_of_week - 1 - subject.start_date.weekday()) % 7)


def subject_event_fields(subject: Subject, tz: ZoneInfo) -> dict:
    """The weekly recurring class event of a timetable subject (T4/T5)."""
    day = first_class_day(subject)
    until = datetime.combine(subject.end_date, time(23, 59, 59), tz).astimezone(UTC)
    details = [f"Mã HP: {subject.code}" if subject.code else "",
               f"Giảng viên: {subject.lecturer}" if subject.lecturer else ""]
    return {
        "title": subject.name,
        "location": subject.room,
        "description": "\n".join(line for line in details if line) or None,
        "start_at": datetime.combine(day, subject.start_time, tz),
        "end_at": datetime.combine(day, subject.end_time, tz),
        "all_day": False,
        "rrule": f"FREQ=WEEKLY;BYDAY={BYDAY[subject.day_of_week - 1]};UNTIL={until:%Y%m%dT%H%M%SZ}",
    }


def subject_follows_event(subject: Subject, event: Event, tz: ZoneInfo) -> None:
    """A class series changed on Google: copy its name, room, weekday and times back to the subject.

    Skipped when the series no longer fits a subject (all-day, or ends on another day).
    """
    start, end = event.start_at.astimezone(tz), event.end_at.astimezone(tz)
    if event.all_day or start.date() != end.date():
        return
    subject.name = event.title
    subject.room = event.location[:100] if event.location else None
    subject.day_of_week = start.isoweekday()
    subject.start_time, subject.end_time = start.timetz().replace(tzinfo=None), end.timetz().replace(tzinfo=None)


def todo_event_fields(todo: Todo) -> dict | None:
    """The todo's own calendar block: only a todo with a fixed slot has one, and not once done.

    A deadline is a moment, not a block of time: it is shown by reminders and planned for by
    CP-SAT study blocks, never as an event of its own.
    """
    if todo.status is TodoStatus.DONE or not (todo.start_at and todo.end_at):
        return None
    return {"title": todo.title, "description": todo.description, "start_at": todo.start_at,
            "end_at": todo.end_at, "all_day": False, "rrule": None}


def todo_own_event(todo: Todo) -> Event | None:
    """The todo's own block on the calendar: its first linked `other` event."""
    return next((event for event in todo.events if event.kind is EventKind.OTHER), None)


def follow_todo(db: Session, user: User, todo: Todo) -> None:
    """Keep a todo's events in line with it after a create or edit (pushed on the next sync):
    its study blocks carry its title, and its own `other` event shows its slot or deadline."""
    for event in todo.events:
        if event.kind is EventKind.STUDY and event.title != todo.title:
            event.title = todo.title
            mark_changed(event, user)
    own = todo_own_event(todo)
    fields = todo_event_fields(todo)
    if fields is None:
        if own is not None:
            delete_todo_event(db, user, own)
        return
    if own is None:
        db.add(Event(user_id=user.id, todo=todo, kind=EventKind.OTHER, source=EventSource.MANUAL,
                     sync_status=initial_sync_status(user), **fields))
    elif any(getattr(own, field) != value for field, value in fields.items()):
        for field, value in fields.items():
            setattr(own, field, value)
        mark_changed(own, user)


def delete_todo_event(db: Session, user: User, event: Event) -> None:
    """Delete a todo's own event; its Google copy goes on the next sync."""
    forget_google_copy(db, user, event)
    db.delete(event)
