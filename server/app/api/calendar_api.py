import logging
import uuid
from dataclasses import asdict
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Header, Response

from app.core.deps import CurrentUser, DbSession, response_context
from app.core.errors import ApiError
from app.db.session import SessionLocal
from app.models.user import User
from app.schemas.calendar import (
    CalendarSettingsUpdate,
    CalendarStatus,
    ConflictResolveRequest,
    SyncConflictList,
    SyncConflictRead,
    SyncRequest,
    SyncResult,
)
from app.schemas.event import EventRead
from app.schemas.user import GoogleSignInRequest
from app.service import calendar_sync
from app.service.google import CALENDAR_SCOPE, GoogleClient, GoogleDep, GoogleError, GoogleUnavailable

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/calendar", tags=["Google Calendar"])


def _status(db: DbSession, user: User) -> CalendarStatus:
    return CalendarStatus.model_validate(calendar_sync.status(db, user), context=response_context(user))


@router.get("/status", response_model=CalendarStatus)
def get_calendar_status(user: CurrentUser, db: DbSession):
    """G1 · Connection and last sync info."""
    return _status(db, user)


@router.post("/connection", response_model=CalendarStatus)
def connect_calendar(body: GoogleSignInRequest, user: CurrentUser, db: DbSession, google: GoogleDep):
    """G6 · Connect (or re-grant) Google Calendar with a new `server_auth_code`."""
    try:
        grant = google.exchange_code(body.server_auth_code)
    except GoogleUnavailable as exc:
        raise calendar_sync.api_error(exc) from exc
    except GoogleError as exc:
        raise ApiError(400, "GOOGLE_CODE_INVALID", "Google rejected the server_auth_code") from exc
    if CALENDAR_SCOPE not in grant.scopes:
        raise ApiError(403, "GOOGLE_SCOPE_MISSING", "Google Calendar scope not granted")
    if calendar_sync.save_connection(db, user, grant) is None:
        raise ApiError(400, "GOOGLE_CODE_INVALID",
                       "Google sent no refresh token; request offline access (forceCodeForRefreshToken)")
    db.flush()
    return _status(db, user)


@router.delete("/connection", status_code=204)
def disconnect_calendar(user: CurrentUser, db: DbSession, google: GoogleDep):
    """G7 · Disconnect; local events stay with `sync_status = not_synced`."""
    calendar_sync.disconnect(db, user, google)
    return Response(status_code=204)


@router.patch("/settings", response_model=CalendarStatus)
def update_calendar_settings(body: CalendarSettingsUpdate, user: CurrentUser, db: DbSession,
                             google: GoogleDep):
    """G8 · Change the target calendar or turn two-way sync on/off."""
    changes = body.changes()
    calendar_sync.update_settings(db, user, google, calendar_id=changes.get("calendar_id"),
                                  two_way_sync=changes.get("two_way_sync"))
    return _status(db, user)


@router.post("/sync", response_model=SyncResult)
def sync_calendar(user: CurrentUser, db: DbSession, google: GoogleDep, body: SyncRequest | None = None):
    """G2 · Push pending events and deletions; pull Google changes when two-way."""
    result = calendar_sync.sync(db, user, google, body.event_ids if body else None)
    return SyncResult(**asdict(result))


@router.get("/conflicts", response_model=SyncConflictList)
def list_calendar_conflicts(user: CurrentUser, db: DbSession):
    """G3 · Unresolved sync conflicts, oldest first."""
    ctx = response_context(user)
    items = [
        SyncConflictRead.model_validate({
            "id": conflict.id,
            "event_id": conflict.event_id,
            "local": EventRead.model_validate(conflict.event, context=ctx),
            "google": conflict.google_payload,
            "detected_at": conflict.detected_at,
        }, context=ctx)
        for conflict in calendar_sync.list_conflicts(db, user)
    ]
    return SyncConflictList(items=items)


@router.post("/conflicts/{id}/resolve", response_model=EventRead)
def resolve_calendar_conflict(id: uuid.UUID, body: ConflictResolveRequest, user: CurrentUser,
                              db: DbSession):
    """G4 · Keep the local or the Google version."""
    event = calendar_sync.resolve_conflict(db, user, id, body.keep)
    return EventRead.model_validate(event, context=response_context(user))


def _pull_in_background(user_id: uuid.UUID, google: GoogleClient) -> None:
    with SessionLocal() as db:
        user = db.get(User, user_id)
        if user is None or user.calendar_connection is None:
            return
        try:
            calendar_sync.pull_for(db, user, google)
            db.commit()
        except (GoogleError, ApiError) as exc:
            db.rollback()
            logger.warning("Webhook pull for user %s failed: %s", user_id, exc)


@router.post("/webhook", status_code=200, openapi_extra={"security": [{"googleChannelToken": []}]})
def google_calendar_webhook(
    db: DbSession,
    google: GoogleDep,
    background: BackgroundTasks,
    x_goog_channel_id: Annotated[str | None, Header()] = None,
    x_goog_resource_id: Annotated[str | None, Header()] = None,
    x_goog_resource_state: Annotated[str | None, Header()] = None,
    x_goog_channel_token: Annotated[str | None, Header()] = None,
):
    """G5 · Called by Google. Always 200 quickly; the pull runs in the background."""
    user_id = None
    if x_goog_channel_id and x_goog_resource_id:
        user_id = calendar_sync.channel_owner(db, x_goog_channel_id, x_goog_resource_id,
                                              x_goog_channel_token)
    if user_id is None:
        logger.info("Ignored Google notification for channel %s", x_goog_channel_id)
    elif x_goog_resource_state in ("exists", "not_exists"):
        background.add_task(_pull_in_background, user_id, google)
    return Response(status_code=200)
