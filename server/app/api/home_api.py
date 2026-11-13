from dataclasses import asdict
from datetime import timedelta

from fastapi import APIRouter
from sqlalchemy import select

from app.api.biorhythm_api import point_out, window_out
from app.api.event_api import event_read
from app.api.todo_api import todo_reads
from app.core.deps import CurrentUser, DbSession, response_context, user_tz
from app.core.timeutil import day_start, now_utc, today
from app.models.enums import SleepSource, TodoStatus
from app.models.health import SleepLog
from app.repository.event_repository import EventRepository
from app.repository.todo_repository import TodoRepository
from app.schemas.health import SleepLogRead
from app.schemas.home import HomeOverview
from app.service import biorhythm_service
from app.service.event_service import occurrences

router = APIRouter(tags=["Home"])

TODAY_EVENTS = 10
UPCOMING_TODOS = 3


@router.get("/home", response_model=HomeOverview)
def get_home_overview(user: CurrentUser, db: DbSession):
    """O1 · Everything the Home screen needs for "now" in one call."""
    profile = biorhythm_service.require_profile(user)
    tz, now = user_tz(user), now_utc()
    day = today(tz)
    timeline = biorhythm_service.timeline_for(db, user, profile, day, 2)

    point = point_out(timeline.at(now))
    peaks = timeline.windows(day)[0] + timeline.windows(day + timedelta(days=1))[0]
    next_peak = next((w for w in peaks if w.end > now), None)

    start, end = day_start(day, tz), day_start(day + timedelta(days=1), tz)
    events = EventRepository(db).list_candidates(user.id, start, end)
    ctx = response_context(user)
    today_events = [event_read(o.event, ctx, o) for o in occurrences(events, start, end, tz)][:TODAY_EVENTS]
    todos, _ = TodoRepository(db).page(user.id, statuses=(TodoStatus.TODO, TodoStatus.IN_PROGRESS),
                                       limit=UPCOMING_TODOS)

    last_night = db.scalar(select(SleepLog).where(SleepLog.user_id == user.id,
                                                  SleepLog.wake_at > now - timedelta(hours=24))
                           .order_by(SleepLog.wake_at.desc()).limit(1))
    return HomeOverview.model_validate({
        "date": day,
        "now": {**point, "time": now},
        "next_peak_window": window_out(next_peak) if next_peak else None,
        "tonight": asdict(timeline.night(day)),
        "today_events": today_events,
        "upcoming_todos": todo_reads(db, user, todos),
        "sleep_debt_7d_minutes": biorhythm_service.debt_summary(db, user, profile, 7)["total_debt_minutes"],
        "last_night": SleepLogRead.model_validate(last_night, context=ctx) if last_night else None,
        "needs_sleep_confirmation": bool(last_night and last_night.source is SleepSource.SCREEN_INFERRED
                                         and not last_night.confirmed),
        "kss_checkin_due": False,  # KSS check-ins come after the course project
        "model": biorhythm_service.model_summary(db, user, profile),
    }, context=ctx)
