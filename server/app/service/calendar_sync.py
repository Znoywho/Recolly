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
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from app.config import Config
from app.core.errors import ApiError, not_found, validation_error
from app.core.security import channel_token, decrypt, encrypt
from app.core.timeutil import now_utc
from app.models.calendar import CalendarConnection, CalendarDeletion
from app.models.enums import ConflictPolicy, ConflictResolution, EventKind, EventSource, SyncMode, SyncStatus
from app.models.event import Event, EventException, SyncConflict
from app.models.user import User
from app.repository.event_repository import EventRepository
from app.service.event_service import subject_follows_event
from app.service.schedule_guard import Busy, make_room
from app.service.google import (
    APP_CALENDAR_SCOPE,
    GoogleAuthRevoked,
    GoogleClient,
    GoogleError,
    GoogleGrant,
    GoogleUnavailable,
)

logger = logging.getLogger(__name__)

FULL_SYNC_DAYS = 30
CHANNEL_RENEW_BEFORE = timedelta(days=1)
# App-triggered syncs inside this window skip the Google pull (webhook pulls are not limited).
PULL_COOLDOWN = timedelta(minutes=2)
TO_PUSH = (SyncStatus.PENDING, SyncStatus.ERROR)
UNTITLED = "(Không có tiêu đề)"
APP_CALENDAR_NAME = "Recolly"
# Fields compared by the three-way merge (two-way sync).
MERGE_FIELDS = ("title", "description", "location", "start_at", "end_at", "all_day", "rrule")
PUSH_QUEUE_KEY = "gcal_push_users"  # Session.info key read by calendar_autopush after commit
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

def queue_push(db: Session, user_id: uuid.UUID) -> None:
    """Ask for an automatic push of this user's pending changes once the transaction commits."""
    db.info.setdefault(PUSH_QUEUE_KEY, set()).add(user_id)


def _target_calendar(user: User, grant: GoogleGrant, google: GoogleClient | None) -> str:
    """Recolly's own calendar when the grant allows creating it, else the primary calendar."""
    if google is None or APP_CALENDAR_SCOPE not in grant.scopes or grant.refresh_token is None:
        return "primary"
    try:
        return google.create_calendar(google.access_token(grant.refresh_token), APP_CALENDAR_NAME, user.timezone)
    except GoogleError as exc:
        logger.warning("Could not create the Recolly calendar, using primary: %s", exc)
        return "primary"


def save_connection(db: Session, user: User, grant: GoogleGrant,
                    google: GoogleClient | None = None) -> CalendarConnection | None:
    """Create or refresh the Calendar link after A1/G6 granted the calendar scope.

    A new link writes to a "Recolly" calendar when the app-calendar scope was granted.
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
    conn = CalendarConnection(user_id=user.id, google_email=grant.email,
                              calendar_id=_target_calendar(user, grant, google),
                              sync_mode=SyncMode.PUSH, conflict_policy=ConflictPolicy.ASK,
                              refresh_token_encrypted=encrypted)
    user.calendar_connection = conn
    db.flush()
    # Everything created before connecting goes up on the first sync.
    db.execute(update(Event)
               .where(Event.user_id == user.id, Event.sync_status == SyncStatus.NOT_SYNCED)
               .values(sync_status=SyncStatus.PENDING))
    queue_push(db, user.id)
    return conn


def _delete_app_calendar(conn: CalendarConnection, google: GoogleClient, refresh_token: str) -> None:
    """Delete the "Recolly" calendar on disconnect (best effort).

    The app only holds calendar.events + calendar.app.created, so Google refuses (403) to delete
    any calendar the app did not create, e.g. one the user picked in G8.
    """
    try:
        google.delete_calendar(google.access_token(refresh_token), conn.calendar_id)
    except GoogleError as exc:
        logger.info("Calendar %s kept on disconnect: %s", conn.calendar_id, exc)


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
        if conn.calendar_id != "primary":
            _delete_app_calendar(conn, google, refresh_token)
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
        return {"connected": False, "google_email": None, "calendar_id": None, "sync_mode": SyncMode.OFF,
                "conflict_policy": ConflictPolicy.ASK, "two_way_sync": False, "last_synced_at": None,
                "pending_count": 0, "conflict_count": 0}
    pending = db.scalar(select(func.count()).select_from(Event).where(
        Event.user_id == user.id, Event.sync_status.in_(TO_PUSH)))
    deletions = db.scalar(select(func.count()).select_from(CalendarDeletion).where(
        CalendarDeletion.user_id == user.id))
    conflicts = db.scalar(select(func.count()).select_from(SyncConflict).join(Event).where(
        Event.user_id == user.id, SyncConflict.resolved_at.is_(None)))
    return {"connected": True, "google_email": conn.google_email, "calendar_id": conn.calendar_id,
            "sync_mode": conn.sync_mode, "conflict_policy": conn.conflict_policy,
            "two_way_sync": conn.two_way, "last_synced_at": conn.last_synced_at,
            "pending_count": pending + deletions, "conflict_count": conflicts}


def update_settings(db: Session, user: User, google: GoogleClient, *, calendar_id: str | None = None,
                    sync_mode: SyncMode | None = None, conflict_policy: ConflictPolicy | None = None) -> None:
    """G8. Moving to another calendar re-pushes everything there; old copies are left alone.
    Leaving `off` pushes what changed while paused; only `two_way` keeps a webhook channel."""
    conn = require_connection(user)
    try:
        if calendar_id is not None and calendar_id != conn.calendar_id:
            token = _access_token(conn, google)
            if not google.can_write(token, calendar_id):
                raise validation_error("calendar_id", "Calendar not found or not writable")
            _stop_channel(conn, google, token)
            conn.calendar_id = calendar_id
            conn.sync_token = None
            # Copies pulled from the old calendar belong there, and so do occurrences changed on it.
            series = select(Event.id).where(Event.user_id == user.id)
            db.execute(delete(Event).where(Event.id.in_(select(EventException.moved_event_id)
                                                        .where(EventException.event_id.in_(series)))))
            db.execute(delete(EventException).where(EventException.event_id.in_(series)))
            db.execute(delete(Event).where(Event.user_id == user.id,
                                           Event.source == EventSource.GOOGLE))
            db.execute(update(Event).where(Event.user_id == user.id).values(
                google_event_id=None, google_etag=None, synced_snapshot=None, sync_status=SyncStatus.PENDING))
            queue_push(db, user.id)
        if conflict_policy is not None:
            conn.conflict_policy = conflict_policy
        if sync_mode is not None:
            if conn.sync_mode is SyncMode.OFF and sync_mode is not SyncMode.OFF:
                queue_push(db, user.id)
            conn.sync_mode = sync_mode
        if not conn.two_way:
            conn.sync_token = None
        # Google is only needed here to open or close a push channel.
        wants_channel = conn.two_way and bool(Config.WEBHOOK_BASE_URL)
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
        "extendedProperties": {"private": {"recolly_id": str(event.id)}},
    }
    if event.moved_from is None:  # one occurrence of a series cannot carry a recurrence
        body["recurrence"] = [f"RRULE:{event.rrule}"] if event.rrule else []
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


def apply_google_version(event: Event, snap: dict[str, Any], tz: ZoneInfo) -> None:
    """Take Google's version of an event; a class series also moves its timetable subject."""
    apply_snapshot(event, snap)
    if event.subject is not None and event.rrule:
        subject_follows_event(event.subject, event, tz)


def _utc_iso(value: datetime | str) -> str:
    """One spelling per instant, so a base and a new version compare equal when unchanged."""
    moment = datetime.fromisoformat(value) if isinstance(value, str) else value
    return moment.astimezone(UTC).isoformat()


def event_fields(event: Event) -> dict[str, Any]:
    """The merge fields of a local event, in snapshot form."""
    return {"title": event.title, "description": event.description, "location": event.location,
            "start_at": _utc_iso(event.start_at), "end_at": _utc_iso(event.end_at),
            "all_day": event.all_day, "rrule": event.rrule}


def snapshot_fields(snap: dict[str, Any]) -> dict[str, Any]:
    """The merge fields of a Google snapshot, in the same form as event_fields."""
    return {field: _utc_iso(snap[field]) if field in ("start_at", "end_at") else snap[field]
            for field in MERGE_FIELDS}


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
    event.synced_snapshot = event_fields(event)


def _mark_synced(event: Event, saved: dict[str, Any]) -> None:
    event.google_event_id = saved["id"]
    event.google_etag = saved.get("etag")
    event.sync_status = SyncStatus.SYNCED
    event.last_synced_at = now_utc()
    event.synced_snapshot = event_fields(event)


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
                event: Event, tz: ZoneInfo, result: SyncResult, *, retry: bool = True) -> None:
    """Insert or patch one event; a 412 (also changed on Google) merges, then pushes the result once."""
    body = to_google(event, tz)
    try:
        if event.google_event_id is None:
            saved = _insert(google, token, conn.calendar_id, event, body, reuse_id=True)
        else:
            # Two-way: If-Match makes Google refuse (412) when the event changed there too.
            etag = event.google_etag if conn.two_way else None
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
                _merge_or_conflict(db, conn, event, item, tz, result)
                if retry and event.sync_status in TO_PUSH:  # merged or local wins: now with Google's etag
                    _push_event(db, google, token, conn, event, tz, result, retry=False)
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


def _pull_new_occurrence(db: Session, user: User, item: dict[str, Any], tz: ZoneInfo,
                         result: SyncResult, touched: list[Event]) -> None:
    """One occurrence of a series moved or cancelled on Google: the series skips it, and a moved
    one becomes its own event (later edits of it are pulled like any event)."""
    series = EventRepository(db).get_by_google_id(user.id, item["recurringEventId"])
    if series is None or "originalStartTime" not in item:
        return  # a series this app does not know
    original_start, _ = _google_time(item["originalStartTime"], tz)
    exception = next((e for e in series.exceptions if e.original_start == original_start), None)
    if exception is None:
        exception = EventException(original_start=original_start)
        series.exceptions.append(exception)
    if item.get("status") != "cancelled" and exception.moved_event is None:
        moved = Event(user_id=user.id, kind=series.kind, source=EventSource.GOOGLE, google_event_id=item["id"])
        apply_snapshot(moved, snapshot(item, tz))
        exception.moved_event = moved
        touched.append(moved)
    result.pulled += 1


def _accept_google_etag(event: Event, snap: dict[str, Any]) -> None:
    """Google's version becomes the base; the local event stays pending, so the next push
    (now with Google's etag) writes the local fields over it."""
    event.google_etag = snap["etag"]
    event.synced_snapshot = snapshot_fields(snap)


def _merge_or_conflict(db: Session, conn: CalendarConnection, event: Event, item: dict[str, Any],
                       tz: ZoneInfo, result: SyncResult) -> None:
    """`event` changed in the app and on Google since the last sync (G3/G4).

    Changes to different fields are merged (base = the last synced version); when both sides
    changed the same field, the connection's conflict policy decides.
    """
    snap = snapshot(item, tz)
    google, local, base = snapshot_fields(snap), event_fields(event), event.synced_snapshot
    if base is not None:
        local_changed = {field for field in MERGE_FIELDS if local[field] != base.get(field)}
        google_changed = {field for field in MERGE_FIELDS if google[field] != base.get(field)}
        if not local_changed & google_changed:
            for field in google_changed:
                value = snap[field]
                setattr(event, field, datetime.fromisoformat(value) if field in ("start_at", "end_at") else value)
            _accept_google_etag(event, snap)
            result.pulled += 1
            return
    policy = conn.conflict_policy
    if policy is ConflictPolicy.LATEST:
        google_newer = datetime.fromisoformat(snap["updated_at"]) > event.updated_at
        policy = ConflictPolicy.GOOGLE if google_newer else ConflictPolicy.LOCAL
    if policy is ConflictPolicy.GOOGLE:
        event.google_event_id = item["id"]
        apply_google_version(event, snap, tz)
        result.pulled += 1
    elif policy is ConflictPolicy.LOCAL:
        _accept_google_etag(event, snap)
    else:
        _record_conflict(db, event, item, tz)
        result.conflicts += 1


def _apply_pulled(db: Session, user: User, item: dict[str, Any], tz: ZoneInfo,
                  result: SyncResult, touched: list[Event]) -> None:
    """Apply one changed Google item; events added or re-timed by Google go into `touched`."""
    events = EventRepository(db)
    local = events.get_by_google_id(user.id, item["id"])
    # An occurrence inherits the series' recolly_id, so it is only ever found by its own id.
    if local is None and not item.get("recurringEventId"):
        recolly_id = ((item.get("extendedProperties") or {}).get("private") or {}).get("recolly_id")
        try:
            local = events.get_owned(uuid.UUID(recolly_id), user.id) if recolly_id else None
        except ValueError:
            local = None
    cancelled = item.get("status") == "cancelled"

    if local is None and item.get("recurringEventId"):
        _pull_new_occurrence(db, user, item, tz, result, touched)
        return
    if local is None:
        if cancelled:
            return
        event = Event(user_id=user.id, kind=EventKind.OTHER, source=EventSource.GOOGLE,
                      google_event_id=item["id"])
        apply_snapshot(event, snapshot(item, tz))
        db.add(event)
        touched.append(event)
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
        _merge_or_conflict(db, user.calendar_connection, local, item, tz, result)
        return
    local.google_event_id = item["id"]
    apply_google_version(local, snapshot(item, tz), tz)
    touched.append(local)
    result.pulled += 1


def _pull(db: Session, user: User, conn: CalendarConnection, google: GoogleClient, token: str,
          tz: ZoneInfo, result: SyncResult) -> None:
    """Pull changes since the sync token; CP-SAT blocks under what Google added or moved make room."""
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
    touched: list[Event] = []
    # Occurrences last: on a full sync their series may come later in the list.
    for item in sorted(items, key=lambda item: bool(item.get("recurringEventId"))):
        _apply_pulled(db, user, item, tz, result, touched)
    db.flush()
    now = now_utc()
    make_room(db, user, [event for event in touched if event in db and event.end_at > now], [])


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
         event_ids: list[uuid.UUID] | None = None, *, pull: bool = True) -> SyncResult:
    """G2: push deletions and pending events, then pull Google changes when two-way.
    `pull=False` is the automatic push after a change (calendar_autopush)."""
    conn = require_connection(user)
    if conn.sync_mode is SyncMode.OFF:
        raise ApiError(409, "CALENDAR_SYNC_OFF", "Google Calendar sync is turned off in settings")
    _lock(db, conn)
    tz = ZoneInfo(user.timezone)
    result = SyncResult()
    should_pull = pull and conn.two_way and not pulled_recently(conn)
    try:
        token = _access_token(conn, google)
        _push(db, user, conn, google, token, tz, result, event_ids)
        if should_pull:
            _pull(db, user, conn, google, token, tz, result)
            _renew_channel(conn, google, token)
            _push(db, user, conn, google, token, tz, result, event_ids)  # what the pull merged
    except GoogleError as exc:
        # Keep what already reached Google; otherwise stale etags would look like conflicts.
        db.commit()
        raise api_error(exc) from exc
    # A push-only sync inside the cooldown must not extend it, or spamming would block pulls forever.
    if should_pull or not conn.two_way:
        conn.last_synced_at = now_utc()
    db.flush()
    logger.info("GCal sync user=%s %s", user.id, result)
    return result


def pulled_recently(conn: CalendarConnection) -> bool:
    """True when Google was already pulled (a sync token exists) and now − last_synced_at < cooldown.

    No sync token means no pull yet (two-way just turned on, or calendar changed), so never block it.
    """
    return (conn.sync_token is not None and conn.last_synced_at is not None
            and now_utc() - conn.last_synced_at < PULL_COOLDOWN)


def channel_owner(db: Session, channel_id: str, resource_id: str, token: str | None) -> uuid.UUID | None:
    """G5: the user behind a verified Google notification, or None to ignore it."""
    conn = db.scalar(select(CalendarConnection).where(CalendarConnection.channel_id == channel_id))
    if conn is None or conn.channel_resource_id != resource_id or not conn.two_way:
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
    logger.info("GCal webhook pull user=%s %s", user.id, result)
    return result


def daily_maintenance(db: Session, user: User, google: GoogleClient) -> bool:
    """Daily job for a two-way user: renew a push channel close to expiry, and pull when no
    channel is alive (no WEBHOOK_BASE_URL, watch failed, or it expired). Returns True if it pulled."""
    conn = require_connection(user)
    _renew_channel(conn, google, _access_token(conn, google))
    if conn.channel_expires_at is not None and conn.channel_expires_at > now_utc():
        return False
    pull_for(db, user, google)
    return True


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
        apply_google_version(event, conflict.google_payload, ZoneInfo(user.timezone))
    else:
        event.google_etag = conflict.google_payload.get("etag")
        event.sync_status = SyncStatus.PENDING
    conflict.resolved_at = now_utc()
    conflict.resolution = keep
    db.flush()
    return event


# ─────────────────────────── Busy times ───────────────────────────

def google_busy(user: User, google: GoogleClient, start: datetime, end: datetime) -> list[Busy]:
    """Busy times on the primary Google calendar in [start, end); [] when sync is off or Google fails.

    Skips Recolly's own events, and everything when two-way already pulls the primary calendar.
    """
    conn = user.calendar_connection
    if conn is None or conn.sync_mode is SyncMode.OFF or (conn.two_way and conn.calendar_id == "primary"):
        return []
    try:
        items = google.busy_events(_access_token(conn, google), "primary", start, end)
    except GoogleError as exc:
        logger.warning("Busy times of user %s unavailable: %s", user.id, exc)
        return []
    return [Busy(datetime.fromisoformat(item["start"]["dateTime"]), datetime.fromisoformat(item["end"]["dateTime"]),
                 item.get("summary") or UNTITLED)
            for item in items
            if not ((item.get("extendedProperties") or {}).get("private") or {}).get("recolly_id")]
