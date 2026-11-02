import uuid
from datetime import datetime, timedelta
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Query, Response
from pydantic import AwareDatetime
from sqlalchemy.orm import Session

from app.core.deps import CurrentUser, DbSession, response_context, user_tz
from app.core.errors import ApiError, not_found, validation_error
from app.models.enums import EventKind, EventSource
from app.models.event import Event
from app.models.todo import Todo
from app.models.user import User
from app.repository.base_repository import BaseRepository
from app.repository.event_repository import EventRepository
from app.schemas.event import EventInput, EventList, EventRead, EventUpdate
from app.service.event_service import (
    Occurrence,
    forget_google_copy,
    initial_sync_status,
    mark_changed,
    normalize_rrule,
    occurrences,
    parse_rrule,
)

router = APIRouter(prefix="/events", tags=["Events"])

MAX_RANGE = timedelta(days=62)


def event_read(event: Event, ctx: dict, occurrence: Occurrence | None = None) -> EventRead:
    """Event response; a recurring instance carries its own times plus `occurrence_start`."""
    read = EventRead.model_validate(event, context=ctx)
    if occurrence is None or not occurrence.recurring:
        return read
    tz = ctx["tz"]
    return read.model_copy(update={"start_at": occurrence.start.astimezone(tz),
                                   "end_at": occurrence.end.astimezone(tz),
                                   "occurrence_start": occurrence.start.astimezone(tz)})


def checked_rrule(rule: str | None, start_at: datetime, tz: ZoneInfo) -> str | None:
    if rule is None:
        return None
    try:
        parse_rrule(rule, start_at, tz)
    except ValueError as exc:
        raise validation_error("rrule", f"Invalid RRULE: {exc}") from exc
    return normalize_rrule(rule, tz)


def check_todo(db: Session, user: User, todo_id: uuid.UUID | None) -> None:
    if todo_id is not None and BaseRepository(Todo, db).get_owned(todo_id, user.id) is None:
        raise not_found("todo")


@router.get("", response_model=EventList)
def list_events(
    user: CurrentUser,
    db: DbSession,
    from_: Annotated[AwareDatetime, Query(alias="from")],
    to: AwareDatetime,
    kind: EventKind | None = None,
    source: EventSource | None = None,
):
    """E1 · Events in [from, to); recurring series are expanded into instances."""
    if to <= from_:
        raise ApiError(400, "INVALID_RANGE", "`to` must be after `from`")
    if to - from_ > MAX_RANGE:
        raise ApiError(400, "RANGE_TOO_LARGE", "Range is longer than 62 days")
    events = EventRepository(db).list_candidates(user.id, from_, to, kind, source)
    ctx = response_context(user)
    return EventList(items=[event_read(o.event, ctx, o)
                            for o in occurrences(events, from_, to, user_tz(user))])


@router.post("", response_model=EventRead, status_code=201)
def create_event(body: EventInput, user: CurrentUser, db: DbSession):
    """E2 · Create an event (`source = manual`)."""
    check_todo(db, user, body.todo_id)
    event = EventRepository(db).create(Event(
        user_id=user.id,
        title=body.title,
        description=body.description,
        location=body.location,
        start_at=body.start_at,
        end_at=body.end_at,
        all_day=body.all_day,
        rrule=checked_rrule(body.rrule, body.start_at, user_tz(user)),
        kind=body.kind,
        source=EventSource.MANUAL,
        todo_id=body.todo_id,
        sync_status=initial_sync_status(user),
    ))
    return event_read(event, response_context(user))


def _get_event(db: Session, user: User, event_id: uuid.UUID) -> Event:
    event = EventRepository(db).get_owned(event_id, user.id)
    if event is None:
        raise not_found("event")
    return event


@router.get("/{id}", response_model=EventRead)
def get_event(id: uuid.UUID, user: CurrentUser, db: DbSession):
    """E3 · Event detail (the series for a recurring event)."""
    return event_read(_get_event(db, user, id), response_context(user))


@router.patch("/{id}", response_model=EventRead)
def update_event(id: uuid.UUID, body: EventUpdate, user: CurrentUser, db: DbSession):
    """E4 · Edit an event (or the whole series); a synced event becomes `pending`."""
    event = _get_event(db, user, id)
    changes = body.changes()
    if changes.get("kind") is EventKind.CLASS and event.subject_id is None:
        raise validation_error("kind", "kind `class` is reserved for timetable events")
    if "todo_id" in changes:
        check_todo(db, user, changes["todo_id"])
    start_at = changes.get("start_at", event.start_at)
    end_at = changes.get("end_at", event.end_at)
    if end_at <= start_at:
        raise ApiError(400, "INVALID_RANGE", "end_at must be after start_at")
    if "rrule" in changes or "start_at" in changes:  # a pulled rule stays untouched otherwise
        changes["rrule"] = checked_rrule(changes.get("rrule", event.rrule), start_at, user_tz(user))
    for field, value in changes.items():
        setattr(event, field, value)
    mark_changed(event, user)
    db.flush()
    return event_read(event, response_context(user))


@router.delete("/{id}", status_code=204)
def delete_event(id: uuid.UUID, user: CurrentUser, db: DbSession):
    """E5 · Delete an event (the whole series); its Google copy goes on the next sync."""
    event = _get_event(db, user, id)
    forget_google_copy(db, user, event)
    db.delete(event)
    db.flush()
    return Response(status_code=204)
