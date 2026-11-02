"""Google Calendar sync (R30, R31, R45).

PostgreSQL is the source of truth. While a user is connected, every new or edited event is
`pending` and POST /calendar/sync pushes it. With two-way sync, changes made on Google are
pulled with a syncToken; an event changed on both sides becomes a SyncConflict (G3/G4).
Events are inserted with id = local UUID hex, so a retried push never creates a duplicate.
"""

import hmac
import logging
import uuid
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from app.config import Config
from app.core.errors import ApiError, not_found, validation_error
from app.core.security import channel_token, decrypt, encrypt
from app.core.timeutil import now_utc
from app.models.calendar import CalendarConnection, CalendarDeletion
from app.models.enums import ConflictResolution, EventKind, EventSource, SyncStatus
from app.models.event import Event, SyncConflict
from app.models.user import User
from app.repository.event_repository import EventRepository
from app.service.google import GoogleAuthRevoked, GoogleClient, GoogleError, GoogleGrant, GoogleUnavailable

logger = logging.getLogger(__name__)

FULL_SYNC_DAYS = 30
CHANNEL_RENEW_BEFORE = timedelta(days=1)
TO_PUSH = (SyncStatus.PENDING, SyncStatus.ERROR)
UNTITLED = "(Không có tiêu đề)"
# Google Calendar colorId per kind, so classes and study blocks are easy to tell apart.
COLOR_IDS = {EventKind.CLASS: "9", EventKind.STUDY: "10", EventKind.REST: "2", EventKind.BEDTIME: "8"}


@dataclass
class SyncResult:
    pushed: int = 0
    pulled: int = 0
    failed: int = 0
    conflicts: int = 0


def api_error(exc: GoogleError) -> ApiError:
    if isinstance(exc, GoogleAuthRevoked) or exc.status == 403:
        return ApiError(403, "GOOGLE_SCOPE_MISSING",
                        "Google Calendar access was revoked or expired; connect again")
    if "not configured" in exc.reason:
        return ApiError(503, "GOOGLE_UNAVAILABLE", exc.reason)
    return ApiError(503, "GOOGLE_UNAVAILABLE", "Google Calendar is not reachable right now")


def require_connection(user: User) -> CalendarConnection:
    if user.calendar_connection is None:
        raise ApiError(409, "CALENDAR_NOT_CONNECTED", "Google Calendar is not connected")
    return user.calendar_connection


def _access_token(conn: CalendarConnection, google: GoogleClient) -> str:
    try:
        refresh_token = decrypt(conn.refresh_token_encrypted)
    except ApiError:
        raise
    except Exception:  # key rotated or data corrupted: same as a revoked grant
        raise GoogleAuthRevoked(401, "stored refresh token cannot be decrypted") from None
    return google.access_token(refresh_token)


# ─────────────────────────── Connection ───────────────────────────

def save_connection(db: Session, user: User, grant: GoogleGrant) -> CalendarConnection | None:
    """Create or refresh the Calendar link after A1/G6 granted the calendar scope.

    Returns None when Google sent no refresh token and nothing is stored yet.
    """
    conn = user.calendar_connection
    if grant.refresh_token is None:
        return conn
    encrypted = encrypt(grant.refresh_token)
    if conn is not None:
        conn.google_email = grant.email
        conn.refresh_token_encrypted = encrypted
        return conn
    conn = CalendarConnection(user_id=user.id, google_email=grant.email, calendar_id="primary",
                              two_way_sync=False, refresh_token_encrypted=encrypted)
    user.calendar_connection = conn
    db.flush()
    # Everything created before connecting goes up on the first sync.
    db.execute(update(Event)
               .where(Event.user_id == user.id, Event.sync_status == SyncStatus.NOT_SYNCED)
               .values(sync_status=SyncStatus.PENDING))
    return conn


def disconnect(db: Session, user: User, google: GoogleClient) -> None:
    """G7: stop the channel, revoke Google access, keep local events as `not_synced`."""
    conn = user.calendar_connection
    if conn is None:
        return
    try:
        refresh_token = decrypt(conn.refresh_token_encrypted)
    except Exception:
        refresh_token = None
    if refresh_token:
        if conn.channel_id and conn.channel_resource_id:
            try:
                google.stop_channel(google.access_token(refresh_token), conn.channel_id,
                                    conn.channel_resource_id)
            except GoogleError as exc:
                logger.info("Could not stop channel %s: %s", conn.channel_id, exc)
        google.revoke(refresh_token)
    event_ids = select(Event.id).where(Event.user_id == user.id)
    db.execute(delete(SyncConflict).where(SyncConflict.event_id.in_(event_ids),
                                          SyncConflict.resolved_at.is_(None)))
    db.execute(delete(CalendarDeletion).where(CalendarDeletion.user_id == user.id))
    db.execute(update(Event).where(Event.user_id == user.id)
               .values(sync_status=SyncStatus.NOT_SYNCED))
    db.delete(conn)
    user.calendar_connection = None
    db.flush()


def status(db: Session, user: User) -> dict[str, Any]:
    conn = user.calendar_connection
    if conn is None:
        return {"connected": False, "google_email": None, "calendar_id": None,
                "two_way_sync": False, "last_synced_at": None, "pending_count": 0,
                "conflict_count": 0}
    pending = db.scalar(select(func.count()).select_from(Event).where(
        Event.user_id == user.id, Event.sync_status.in_(TO_PUSH)))
    deletions = db.scalar(select(func.count()).select_from(CalendarDeletion).where(
        CalendarDeletion.user_id == user.id))
    conflicts = db.scalar(select(func.count()).select_from(SyncConflict).join(Event).where(
        Event.user_id == user.id, SyncConflict.resolved_at.is_(None)))
    return {"connected": True, "google_email": conn.google_email, "calendar_id": conn.calendar_id,
            "two_way_sync": conn.two_way_sync, "last_synced_at": conn.last_synced_at,
            "pending_count": pending + deletions, "conflict_count": conflicts}


def update_settings(db: Session, user: User, google: GoogleClient, *,
                    calendar_id: str | None = None, two_way_sync: bool | None = None) -> None:
    """G8. Moving to another calendar re-pushes everything there; old copies are left alone."""
    conn = require_connection(user)
    try:
        if calendar_id is not None and calendar_id != conn.calendar_id:
            token = _access_token(conn, google)
            if not google.can_write(token, calendar_id):
                raise validation_error("calendar_id", "Calendar not found or not writable")
            _stop_channel(conn, google, token)
            conn.calendar_id = calendar_id
            conn.sync_token = None
            # Copies pulled from the old calendar belong there.
            db.execute(delete(Event).where(Event.user_id == user.id,
                                           Event.source == EventSource.GOOGLE))
            db.execute(update(Event).where(Event.user_id == user.id).values(
                google_event_id=None, google_etag=None, sync_status=SyncStatus.PENDING))
        if two_way_sync is not None:
            conn.two_way_sync = two_way_sync
        if not conn.two_way_sync:
            conn.sync_token = None
        # Google is only needed here to open or close a push channel.
        wants_channel = conn.two_way_sync and bool(Config.WEBHOOK_BASE_URL)
        if wants_channel or conn.channel_id:
            token = _access_token(conn, google)
            if wants_channel:
                _renew_channel(conn, google, token)
            else:
                _stop_channel(conn, google, token)
    except GoogleError as exc:
        raise api_error(exc) from exc
    db.flush()


# ─────────────────────────── Mapping ───────────────────────────

def to_google(event: Event, tz: ZoneInfo) -> dict[str, Any]:
    body: dict[str, Any] = {
        "summary": event.title,
        "description": event.description,
        "location": event.location,
        "recurrence": [f"RRULE:{event.rrule}"] if event.rrule else [],
        "extendedProperties": {"private": {"recolly_id": str(event.id)}},
    }
    if event.kind in COLOR_IDS:
        body["colorId"] = COLOR_IDS[event.kind]
    if event.all_day:
        start = event.start_at.astimezone(tz).date()
        end = max(event.end_at.astimezone(tz).date(), start + timedelta(days=1))
        body["start"] = {"date": start.isoformat()}
        body["end"] = {"date": end.isoformat()}
    else:
        body["start"] = {"dateTime": event.start_at.astimezone(tz).isoformat(), "timeZone": tz.key}
        body["end"] = {"dateTime": event.end_at.astimezone(tz).isoformat(), "timeZone": tz.key}
    return body


def _google_time(value: dict[str, str], tz: ZoneInfo) -> tuple[datetime, bool]:
    """(start or end, all_day) of a Google event time."""
    if "dateTime" in value:
        return datetime.fromisoformat(value["dateTime"]), False
    return datetime.combine(date.fromisoformat(value["date"]), time(0), tz), True


def snapshot(item: dict[str, Any], tz: ZoneInfo) -> dict[str, Any]:
    """GoogleEventSnapshot of the contract, plus what is needed to apply it later."""
    start, all_day = _google_time(item["start"], tz)
    end, _ = _google_time(item["end"], tz)
    rrule = next((line[6:] for line in item.get("recurrence") or [] if line.startswith("RRULE:")), None)
    return {
        "title": (item.get("summary") or UNTITLED)[:255],
        "description": item.get("description"),
        "location": (item.get("location") or "")[:255] or None,
        "start_at": start.isoformat(),
        "end_at": max(end, start + timedelta(minutes=1)).isoformat(),
        "updated_at": item.get("updated") or now_utc().isoformat(),
        "all_day": all_day,
        "rrule": rrule[:500] if rrule else None,
        "etag": item.get("etag"),
    }


def apply_snapshot(event: Event, snap: dict[str, Any]) -> None:
    event.title = snap["title"]
    event.description = snap["description"]
    event.location = snap["location"]
    event.start_at = datetime.fromisoformat(snap["start_at"])
    event.end_at = datetime.fromisoformat(snap["end_at"])
    event.all_day = snap["all_day"]
    event.rrule = snap["rrule"]
    event.google_etag = snap["etag"]
    event.sync_status = SyncStatus.SYNCED
    event.last_synced_at = now_utc()


def _mark_synced(event: Event, saved: dict[str, Any]) -> None:
    event.google_event_id = saved["id"]
    event.google_etag = saved.get("etag")
    event.sync_status = SyncStatus.SYNCED
    event.last_synced_at = now_utc()


# ─────────────────────────── Push ───────────────────────────

def _insert(google: GoogleClient, token: str, calendar_id: str, event: Event,
            body: dict[str, Any], *, reuse_id: bool) -> dict[str, Any]:
    if not reuse_id:
        return google.insert_event(token, calendar_id, body)
    try:
        return google.insert_event(token, calendar_id, {**body, "id": event.id.hex})
    except GoogleError as exc:
        if exc.status != 409:
            raise
    # 409: an earlier push got through but its answer was lost.
    existing = google.get_event(token, calendar_id, event.id.hex)
    if existing is None or existing.get("status") == "cancelled":
        return google.insert_event(token, calendar_id, body)
    return google.patch_event(token, calendar_id, event.id.hex, body)


def _push_event(db: Session, google: GoogleClient, token: str, conn: CalendarConnection,
                event: Event, tz: ZoneInfo, result: SyncResult) -> None:
    body = to_google(event, tz)
    try:
        if event.google_event_id is None:
            saved = _insert(google, token, conn.calendar_id, event, body, reuse_id=True)
        else:
            # Two-way: If-Match makes Google refuse (412) when the event changed there too.
            etag = event.google_etag if conn.two_way_sync else None
            try:
                saved = google.patch_event(token, conn.calendar_id, event.google_event_id, body, etag)
            except GoogleError as exc:
                if exc.status not in (404, 410):
                    raise
                saved = _insert(google, token, conn.calendar_id, event, body, reuse_id=False)
    except (GoogleAuthRevoked, GoogleUnavailable):
        raise
    except GoogleError as exc:
        if exc.status == 412:
            item = google.get_event(token, conn.calendar_id, event.google_event_id)
            if item is not None:
                _record_conflict(db, event, item, tz)
                result.conflicts += 1
                return
        logger.warning("Push of event %s failed: %s", event.id, exc)
        event.sync_status = SyncStatus.ERROR
        result.failed += 1
        return
    _mark_synced(event, saved)
    result.pushed += 1


def _push(db: Session, user: User, conn: CalendarConnection, google: GoogleClient, token: str,
          tz: ZoneInfo, result: SyncResult, event_ids: list[uuid.UUID] | None) -> None:
    for row in db.scalars(select(CalendarDeletion).where(CalendarDeletion.user_id == user.id)).all():
        try:
            google.delete_event(token, row.calendar_id, row.google_event_id)
        except (GoogleAuthRevoked, GoogleUnavailable):
            raise
        except GoogleError as exc:
            logger.warning("Delete of Google event %s failed: %s", row.google_event_id, exc)
            result.failed += 1
            continue
        db.delete(row)
        result.pushed += 1

    statement = select(Event).where(Event.user_id == user.id, Event.sync_status.in_(TO_PUSH))
    if event_ids is not None:
        statement = statement.where(Event.id.in_(event_ids))
    for event in db.scalars(statement.order_by(Event.start_at)).all():
        _push_event(db, google, token, conn, event, tz, result)


# ─────────────────────────── Pull ───────────────────────────

def _record_conflict(db: Session, event: Event, item: dict[str, Any], tz: ZoneInfo) -> None:
    snap = snapshot(item, tz)
    conflict = db.scalar(select(SyncConflict).where(SyncConflict.event_id == event.id,
                                                    SyncConflict.resolved_at.is_(None)))
    if conflict is None:
        db.add(SyncConflict(event_id=event.id, google_payload=snap, detected_at=now_utc()))
    else:
        conflict.google_payload = snap
        conflict.detected_at = now_utc()
    event.sync_status = SyncStatus.CONFLICT


def _apply_pulled(db: Session, user: User, item: dict[str, Any], tz: ZoneInfo,
                  result: SyncResult) -> None:
    if item.get("recurringEventId"):
        return  # a changed instance of a series: not supported, the series itself is kept
    events = EventRepository(db)
    local = events.get_by_google_id(user.id, item["id"])
    if local is None:
        recolly_id = ((item.get("extendedProperties") or {}).get("private") or {}).get("recolly_id")
        try:
            local = events.get_owned(uuid.UUID(recolly_id), user.id) if recolly_id else None
        except ValueError:
            local = None
    cancelled = item.get("status") == "cancelled"

    if local is None:
        if cancelled:
            return
        event = Event(user_id=user.id, kind=EventKind.OTHER, source=EventSource.GOOGLE,
                      google_event_id=item["id"])
        apply_snapshot(event, snapshot(item, tz))
        db.add(event)
        result.pulled += 1
        return
    if local.google_etag is not None and local.google_etag == item.get("etag"):
        return  # the echo of our own push

    if cancelled:
        if local.sync_status in TO_PUSH or local.subject_id is not None:
            # Local changes win over a delete, and classes stay in the timetable:
            # only the Google copy is forgotten (re-created on the next push if pending).
            local.google_event_id = None
            local.google_etag = None
            if local.sync_status not in TO_PUSH:
                local.sync_status = SyncStatus.NOT_SYNCED
        else:
            db.delete(local)
        result.pulled += 1
        return
    if local.sync_status == SyncStatus.CONFLICT:
        _record_conflict(db, local, item, tz)  # already counted: refresh Google's side only
        return
    if local.sync_status in TO_PUSH:
        _record_conflict(db, local, item, tz)
        result.conflicts += 1
        return
    local.google_event_id = item["id"]
    apply_snapshot(local, snapshot(item, tz))
    result.pulled += 1


def _pull(db: Session, user: User, conn: CalendarConnection, google: GoogleClient, token: str,
          tz: ZoneInfo, result: SyncResult) -> None:
    sync_token, page_token, items = conn.sync_token, None, []
    while True:
        try:
            page = google.list_events(
                token, conn.calendar_id, sync_token=sync_token, page_token=page_token,
                time_min=None if sync_token else now_utc() - timedelta(days=FULL_SYNC_DAYS))
        except GoogleError as exc:
            if exc.status == 410 and sync_token:  # sync token expired: full sync again
                sync_token, page_token, items = None, None, []
                continue
            raise
        items.extend(page.items)
        if page.next_page_token:
            page_token = page.next_page_token
            continue
        conn.sync_token = page.next_sync_token
        break
    for item in items:
        _apply_pulled(db, user, item, tz, result)


# ─────────────────────────── Channels ───────────────────────────

def webhook_address() -> str:
    return f"{Config.WEBHOOK_BASE_URL}/api/v1/calendar/webhook"


def _stop_channel(conn: CalendarConnection, google: GoogleClient, token: str) -> None:
    if conn.channel_id and conn.channel_resource_id:
        try:
            google.stop_channel(token, conn.channel_id, conn.channel_resource_id)
        except GoogleError as exc:
            logger.info("Could not stop channel %s: %s", conn.channel_id, exc)
    conn.channel_id = conn.channel_resource_id = conn.channel_expires_at = None


def _renew_channel(conn: CalendarConnection, google: GoogleClient, token: str) -> None:
    """Keep a push channel open while two-way sync is on (needs WEBHOOK_BASE_URL)."""
    if not Config.WEBHOOK_BASE_URL:
        return
    if conn.channel_id and conn.channel_expires_at and \
            conn.channel_expires_at - now_utc() > CHANNEL_RENEW_BEFORE:
        return
    old = (conn.channel_id, conn.channel_resource_id)
    channel_id = uuid.uuid4().hex
    try:
        resource_id, expires_at = google.watch(token, conn.calendar_id, channel_id,
                                               channel_token(channel_id), webhook_address())
    except GoogleError as exc:
        logger.warning("Could not open a push channel: %s", exc)
        return
    conn.channel_id, conn.channel_resource_id, conn.channel_expires_at = channel_id, resource_id, expires_at
    if old[0] and old[1]:
        try:
            google.stop_channel(token, old[0], old[1])
        except GoogleError:
            pass


# ─────────────────────────── Sync ───────────────────────────

def _lock(db: Session, conn: CalendarConnection) -> None:
    """One sync per user at a time (manual sync and webhook pulls may overlap)."""
    db.execute(select(CalendarConnection.id).where(CalendarConnection.id == conn.id).with_for_update())


def sync(db: Session, user: User, google: GoogleClient,
         event_ids: list[uuid.UUID] | None = None) -> SyncResult:
    """G2: push deletions and pending events, then pull Google changes when two-way."""
    conn = require_connection(user)
    _lock(db, conn)
    tz = ZoneInfo(user.timezone)
    result = SyncResult()
    try:
        token = _access_token(conn, google)
        _push(db, user, conn, google, token, tz, result, event_ids)
        if conn.two_way_sync:
            _pull(db, user, conn, google, token, tz, result)
            _renew_channel(conn, google, token)
    except GoogleError as exc:
        # Keep what already reached Google; otherwise stale etags would look like conflicts.
        db.commit()
        raise api_error(exc) from exc
    conn.last_synced_at = now_utc()
    db.flush()
    return result


def channel_owner(db: Session, channel_id: str, resource_id: str, token: str | None) -> uuid.UUID | None:
    """G5: the user behind a verified Google notification, or None to ignore it."""
    conn = db.scalar(select(CalendarConnection).where(CalendarConnection.channel_id == channel_id))
    if conn is None or conn.channel_resource_id != resource_id or not conn.two_way_sync:
        return None
    if not hmac.compare_digest(token or "", channel_token(channel_id)):
        return None
    return conn.user_id


def pull_for(db: Session, user: User, google: GoogleClient) -> SyncResult:
    """Background pull after a webhook."""
    conn = require_connection(user)
    _lock(db, conn)
    result = SyncResult()
    _pull(db, user, conn, google, _access_token(conn, google), ZoneInfo(user.timezone), result)
    conn.last_synced_at = now_utc()
    return result


# ─────────────────────────── Conflicts ───────────────────────────

def list_conflicts(db: Session, user: User) -> list[SyncConflict]:
    statement = (select(SyncConflict).join(Event)
                 .where(Event.user_id == user.id, SyncConflict.resolved_at.is_(None))
                 .order_by(SyncConflict.detected_at))
    return list(db.scalars(statement).all())


def resolve_conflict(db: Session, user: User, conflict_id: uuid.UUID,
                     keep: ConflictResolution) -> Event:
    """G4. Keeping the local version re-pushes it against Google's latest etag."""
    conflict = db.get(SyncConflict, conflict_id)
    if conflict is None or conflict.event.user_id != user.id:
        raise not_found("conflict")
    if conflict.resolved_at is not None:
        raise ApiError(409, "CONFLICT_ALREADY_RESOLVED", "Conflict already resolved")
    event = conflict.event
    if keep is ConflictResolution.KEEP_GOOGLE:
        apply_snapshot(event, conflict.google_payload)
    else:
        event.google_etag = conflict.google_payload.get("etag")
        event.sync_status = SyncStatus.PENDING
    conflict.resolved_at = now_utc()
    conflict.resolution = keep
    db.flush()
    return event
