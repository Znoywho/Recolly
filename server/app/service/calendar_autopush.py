"""Push a user's calendar changes to Google right after they are committed (sync modes push / two_way).

Every flush notes the users whose events became pending (or were deleted with a Google copy);
after the commit each of them gets a push-only sync on a small worker pool, so API answers do
not wait for Google. The manual POST /calendar/sync stays for retries and pulls.
"""

import logging
import uuid
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from itertools import chain

from sqlalchemy import event
from sqlalchemy.orm import Session

from app.core.errors import ApiError
from app.db.session import SessionLocal
from app.models.calendar import CalendarDeletion
from app.models.enums import SyncMode
from app.models.event import Event
from app.models.user import User
from app.service import calendar_sync
from app.service.google import GoogleClient, GoogleError, get_google_client

logger = logging.getLogger(__name__)

ENABLED = True  # tests turn it off and call push_now themselves
PUSHING_KEY = "gcal_pushing"  # Session.info flag of a push session: its own changes never queue another push
# shortcut: in-process pool, lost on restart (the change stays pending for the next sync); use a queue if it matters.
_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="gcal-push")


def push_now(user_id: uuid.UUID, google: GoogleClient | None = None) -> None:
    """Push one user's pending changes (no pull); errors are logged, the changes stay pending."""
    with SessionLocal() as db:
        db.info[PUSHING_KEY] = True
        user = db.get(User, user_id)
        conn = user.calendar_connection if user else None
        if conn is None or conn.sync_mode is SyncMode.OFF:
            return
        try:
            calendar_sync.sync(db, user, google or get_google_client(), pull=False)
            db.commit()
        except (GoogleError, ApiError) as exc:
            db.rollback()
            logger.warning("Auto push for user %s failed: %s", user_id, exc)


def _submit_to_pool(user_id: uuid.UUID) -> None:
    """Default runner: push in the background."""
    _pool.submit(push_now, user_id)


run: Callable[[uuid.UUID], None] = _submit_to_pool


@event.listens_for(Session, "after_flush")
def _note_changed_users(session: Session, _flush_context) -> None:
    """Remember users whose events now wait for Google (the session still shows what was flushed)."""
    if session.info.get(PUSHING_KEY):
        return
    for obj in chain(session.new, session.dirty):
        if isinstance(obj, Event) and obj.sync_status in calendar_sync.TO_PUSH:
            calendar_sync.queue_push(session, obj.user_id)
        elif isinstance(obj, CalendarDeletion):  # a deleted event's Google copy
            calendar_sync.queue_push(session, obj.user_id)


@event.listens_for(Session, "after_commit")
def _push_after_commit(session: Session) -> None:
    """Start the pushes noted in this transaction."""
    users = session.info.pop(calendar_sync.PUSH_QUEUE_KEY, set())
    if ENABLED and not session.info.get(PUSHING_KEY):
        for user_id in users:
            run(user_id)


@event.listens_for(Session, "after_rollback")
def _forget_after_rollback(session: Session) -> None:
    """Nothing was saved, so nothing is pushed."""
    session.info.pop(calendar_sync.PUSH_QUEUE_KEY, None)
