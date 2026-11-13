import uuid

from fastapi import APIRouter, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import CurrentUser, DbSession, response_context, user_tz
from app.core.errors import ApiError, not_found
from app.models.enums import EventKind, EventSource
from app.models.event import Event
from app.models.timetable import Subject
from app.models.user import User
from app.repository.base_repository import BaseRepository
from app.schemas.timetable import SubjectBulkCreate, SubjectList, SubjectRead, SubjectUpdate
from app.service.event_service import (
    forget_google_copy,
    initial_sync_status,
    mark_changed,
    subject_event_fields,
)

router = APIRouter(prefix="/timetable", tags=["Timetable"])


def _delete_subject(db: Session, user: User, subject: Subject) -> None:
    for event in subject.events:
        forget_google_copy(db, user, event)
    db.delete(subject)  # its class events cascade


@router.get("", response_model=SubjectList)
def list_subjects(user: CurrentUser, db: DbSession):
    """T3 · All subjects of the user, by weekday and start time."""
    subjects = db.scalars(select(Subject).where(Subject.user_id == user.id)
                          .order_by(Subject.day_of_week, Subject.start_time)).all()
    ctx = response_context(user)
    return SubjectList(items=[SubjectRead.model_validate(s, context=ctx) for s in subjects])


@router.post("", response_model=SubjectList, status_code=201)
def create_subjects(body: SubjectBulkCreate, user: CurrentUser, db: DbSession):
    """T4 · Save subjects; each one also becomes a weekly recurring `class` event."""
    tz = user_tz(user)
    if body.replace_existing:
        for subject in db.scalars(select(Subject).where(Subject.user_id == user.id)).all():
            _delete_subject(db, user, subject)
        db.flush()
    created = []
    for item in body.subjects:
        subject = Subject(user_id=user.id, **item.model_dump())
        db.add(subject)
        db.flush()
        db.add(Event(user_id=user.id, subject_id=subject.id, kind=EventKind.CLASS,
                     source=EventSource.MANUAL, sync_status=initial_sync_status(user),
                     **subject_event_fields(subject, tz)))
        created.append(subject)
    db.flush()
    ctx = response_context(user)
    return SubjectList(items=[SubjectRead.model_validate(s, context=ctx) for s in created])


def _get_subject(db: Session, user: User, subject_id: uuid.UUID) -> Subject:
    subject = BaseRepository(Subject, db).get_owned(subject_id, user.id)
    if subject is None:
        raise not_found("subject")
    return subject


@router.patch("/{id}", response_model=SubjectRead)
def update_subject(id: uuid.UUID, body: SubjectUpdate, user: CurrentUser, db: DbSession):
    """T5 · Edit a subject; its class event follows (and becomes `pending` if synced)."""
    subject = _get_subject(db, user, id)
    for field, value in body.changes().items():
        setattr(subject, field, value)
    if subject.end_time <= subject.start_time:
        raise ApiError(400, "INVALID_RANGE", "end_time must be after start_time")
    if subject.end_date < subject.start_date:
        raise ApiError(400, "INVALID_RANGE", "end_date must not be before start_date")
    fields = subject_event_fields(subject, user_tz(user))
    for event in subject.events:
        for field, value in fields.items():
            setattr(event, field, value)
        mark_changed(event, user)
    db.flush()
    return SubjectRead.model_validate(subject, context=response_context(user))


@router.delete("/{id}", status_code=204)
def delete_subject(id: uuid.UUID, user: CurrentUser, db: DbSession):
    """T6 · Delete a subject and its class event (the Google copy goes on the next sync)."""
    _delete_subject(db, user, _get_subject(db, user, id))
    db.flush()
    return Response(status_code=204)
