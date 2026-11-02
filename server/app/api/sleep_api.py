import uuid
from datetime import date, datetime, timedelta
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Query, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import CurrentUser, DbSession, response_context, user_tz
from app.core.errors import ApiError, not_found
from app.core.timeutil import day_start, today
from app.models.enums import SleepSource
from app.models.health import SleepLog
from app.models.user import User
from app.repository.base_repository import BaseRepository
from app.schemas.health import (
    MAX_SLEEP_HOURS,
    SleepDebtSummary,
    SleepLogCreate,
    SleepLogList,
    SleepLogRead,
    SleepLogUpdate,
)
from app.service import biorhythm_service

router = APIRouter(tags=["Sleep logs"])

MAX_LIST_DAYS = 92


def _overlapping(db: Session, user: User, start: datetime, end: datetime,
                 exclude: uuid.UUID | None = None) -> list[SleepLog]:
    statement = select(SleepLog).where(SleepLog.user_id == user.id, SleepLog.sleep_at < end,
                                       SleepLog.wake_at > start)
    if exclude is not None:
        statement = statement.where(SleepLog.id != exclude)
    return list(db.scalars(statement).all())


def _overlap_error() -> ApiError:
    return ApiError(409, "SLEEP_LOG_OVERLAP", "Overlaps another sleep log")


def _date_range(from_: date | None, to: date | None, tz: ZoneInfo) -> tuple[date, date]:
    to = to or today(tz)
    from_ = from_ or to - timedelta(days=13)
    if to < from_:
        raise ApiError(400, "INVALID_RANGE", "`to` must not be before `from`")
    if (to - from_).days + 1 > MAX_LIST_DAYS:
        raise ApiError(400, "RANGE_TOO_LARGE", f"Range is longer than {MAX_LIST_DAYS} days")
    return from_, to


@router.get("/sleep-logs", response_model=SleepLogList)
def list_sleep_logs(
    user: CurrentUser,
    db: DbSession,
    from_: Annotated[date | None, Query(alias="from")] = None,
    to: date | None = None,
    source: SleepSource | None = None,
    confirmed: bool | None = None,
):
    """H3 · Logs whose wake-up date (user timezone) is in [from, to], newest first."""
    tz = user_tz(user)
    from_, to = _date_range(from_, to, tz)
    statement = select(SleepLog).where(SleepLog.user_id == user.id,
                                       SleepLog.wake_at >= day_start(from_, tz),
                                       SleepLog.wake_at < day_start(to + timedelta(days=1), tz))
    if source is not None:
        statement = statement.where(SleepLog.source == source)
    if confirmed is not None:
        statement = statement.where(SleepLog.confirmed.is_(confirmed))
    logs = db.scalars(statement.order_by(SleepLog.wake_at.desc())).all()
    ctx = response_context(user)
    return SleepLogList(items=[SleepLogRead.model_validate(log, context=ctx) for log in logs])


@router.post("/sleep-logs", response_model=SleepLogRead, status_code=201)
def create_sleep_log(body: SleepLogCreate, user: CurrentUser, db: DbSession):
    """H4 · Manual log. An overlapping unconfirmed inferred log is replaced; any other overlap is 409."""
    overlaps = _overlapping(db, user, body.sleep_at, body.wake_at)
    if any(log.source is not SleepSource.SCREEN_INFERRED or log.confirmed for log in overlaps):
        raise _overlap_error()
    for log in overlaps:
        db.delete(log)
    log = SleepLog(user_id=user.id, sleep_at=body.sleep_at, wake_at=body.wake_at, quality=body.quality,
                   note=body.note, source=SleepSource.MANUAL, confirmed=True)
    db.add(log)
    db.flush()
    return SleepLogRead.model_validate(log, context=response_context(user))


def _get_log(db: Session, user: User, log_id: uuid.UUID) -> SleepLog:
    log = BaseRepository(SleepLog, db).get_owned(log_id, user.id)
    if log is None:
        raise not_found("sleep_log")
    return log


@router.patch("/sleep-logs/{id}", response_model=SleepLogRead)
def update_sleep_log(id: uuid.UUID, body: SleepLogUpdate, user: CurrentUser, db: DbSession):
    """H5 · Edit a log; editing an inferred log also confirms it."""
    log = _get_log(db, user, id)
    for field, value in body.changes().items():
        setattr(log, field, value)
    if log.wake_at <= log.sleep_at or log.wake_at - log.sleep_at > timedelta(hours=MAX_SLEEP_HOURS):
        raise ApiError(400, "INVALID_RANGE", f"wake_at must be after sleep_at, at most {MAX_SLEEP_HOURS} h")
    if _overlapping(db, user, log.sleep_at, log.wake_at, exclude=log.id):
        raise _overlap_error()
    log.confirmed = True
    db.flush()
    return SleepLogRead.model_validate(log, context=response_context(user))


@router.delete("/sleep-logs/{id}", status_code=204)
def delete_sleep_log(id: uuid.UUID, user: CurrentUser, db: DbSession):
    """H6 · Delete a sleep log."""
    db.delete(_get_log(db, user, id))
    db.flush()
    return Response(status_code=204)


@router.get("/sleep-debt", response_model=SleepDebtSummary)
def get_sleep_debt(user: CurrentUser, db: DbSession,
                   days: Annotated[int, Query(ge=1, le=30)] = 7):
    """H7 · Need − slept per wake-up date, social jetlag from real logs, sleep pressure now."""
    profile = biorhythm_service.require_profile(user)
    return SleepDebtSummary(**biorhythm_service.debt_summary(db, user, profile, days))
