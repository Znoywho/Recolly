from dataclasses import asdict

from fastapi import APIRouter
from sqlalchemy import select

from app.api.event_api import event_read
from app.core.deps import CurrentUser, DbSession, response_context
from app.core.errors import validation_error
from app.core.timeutil import now_utc
from app.models.enums import EventKind, EventSource
from app.models.event import Event
from app.models.todo import Todo
from app.schemas.calendar import SyncResult
from app.schemas.schedule import (
    ScheduleApplyRequest,
    ScheduleApplyResult,
    ScheduleGenerateRequest,
    ScheduleSuggestion,
)
from app.service import biorhythm_service, calendar_sync, scheduler
from app.service.event_service import initial_sync_status
from app.service.google import GoogleDep

router = APIRouter(prefix="/schedule", tags=["Scheduler"])


@router.post("/generate", response_model=ScheduleSuggestion)
def generate_schedule(body: ScheduleGenerateRequest, user: CurrentUser, db: DbSession):
    """S1 · CP-SAT study blocks for [from, to]; nothing is saved, the suggestion lives 1 hour."""
    profile = biorhythm_service.require_profile(user)
    days = scheduler.check_range(body.from_, body.to)
    timeline = biorhythm_service.timeline_for(db, user, profile, body.from_, days)
    result = scheduler.generate(db, user, timeline, body.from_, body.to, body.todo_ids, body.options,
                                now_utc())
    result["model"] = biorhythm_service.model_summary(db, user, profile)
    return ScheduleSuggestion.model_validate(result, context=response_context(user))


@router.post("/apply", response_model=ScheduleApplyResult, status_code=201)
def apply_schedule(body: ScheduleApplyRequest, user: CurrentUser, db: DbSession, google: GoogleDep):
    """S2 · Save the chosen blocks as events (`source = scheduler`); optionally push them now."""
    suggestion = scheduler.get_suggestion(user, body.suggestion_id, now_utc())
    blocks = suggestion.blocks
    if body.block_indexes is not None:
        unknown = sorted({i for i in body.block_indexes if not 0 <= i < len(blocks)})
        if unknown:
            raise validation_error("block_indexes", f"Unknown block indexes: {unknown}")
        blocks = [blocks[i] for i in sorted(set(body.block_indexes))]

    # A todo may have been deleted since S1.
    todo_ids = {b["todo_id"] for b in blocks if b["todo_id"]}
    existing = set(db.scalars(select(Todo.id).where(Todo.user_id == user.id, Todo.id.in_(todo_ids))).all())
    events = [Event(user_id=user.id, title=b["title"], start_at=b["start_at"], end_at=b["end_at"],
                    kind=EventKind(b["kind"]), source=EventSource.SCHEDULER,
                    todo_id=b["todo_id"] if b["todo_id"] in existing else None,
                    sync_status=initial_sync_status(user))
              for b in blocks]
    db.add_all(events)
    db.flush()
    scheduler.discard_suggestion(body.suggestion_id)

    sync = None
    if body.sync_to_google and user.calendar_connection is not None:
        sync = SyncResult(**asdict(calendar_sync.sync(db, user, google, [e.id for e in events])))
    ctx = response_context(user)
    return ScheduleApplyResult(events=[event_read(e, ctx) for e in events], sync=sync)
