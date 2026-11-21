"""Send due bedtime / deadline reminders (R39) to every registered device.

Run every 5 minutes (cron now, a Kubernetes CronJob when deployed):
    python -m app.jobs.send_reminders
Each run covers the window [now − RUN_EVERY, now).
Each reminder is claimed once in the store (Redis SET NX), so an extra run in the same window
does not send it twice. Needs REDIS_URL: each cron run is a new process, so MemoryStore forgets.
shortcut: a missed run skips its reminders, and a claimed reminder whose pushes all fail is not retried;
add catch-up / retry if users report missed reminders.
"""

import hashlib
import json
import logging
from collections import Counter
from datetime import datetime, timedelta

from sqlalchemy import select

from app.core.redis_client import MemoryStore, RedisStore, get_store
from app.core.timeutil import now_utc
from app.db.session import SessionLocal
from app.models.notification import Device
from app.models.user import User
from app.service.push import FcmSender, LogSender, get_push_sender
from app.service.reminders import due_reminders

logger = logging.getLogger(__name__)

RUN_EVERY = timedelta(minutes=5)
CLAIM_TTL_SECONDS = 24 * 3600  # far longer than any overlap between runs


def reminder_claim_key(user_id, payload: dict) -> str:
    """Store key for one reminder: same user + same payload = same reminder."""
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    return f"reminder:{user_id}:{digest}"


def run_send_reminders(now: datetime | None = None, sender: FcmSender | LogSender | None = None,
                       store: RedisStore | MemoryStore | None = None) -> Counter:
    """Send what fell due in the last RUN_EVERY to each user's devices; one failing user skips only itself."""
    now = now or now_utc()
    sender = sender or get_push_sender()
    store = store or get_store()
    with SessionLocal() as db:
        user_ids = db.scalars(select(Device.user_id).distinct()).all()
    counts: Counter = Counter()
    for user_id in user_ids:
        with SessionLocal() as db:
            try:
                user = db.get(User, user_id)
                dead: set = set()
                for payload in due_reminders(db, user, now - RUN_EVERY, now):
                    if not store.set_if_absent(reminder_claim_key(user_id, payload), "1", CLAIM_TTL_SECONDS):
                        counts["duplicates"] += 1
                        continue
                    for device in user.devices:
                        if device.id in dead:
                            continue
                        try:
                            delivered = sender.send(device.fcm_token, payload)
                        except Exception as exc:  # noqa: BLE001 - one bad device must not block the user's others
                            counts["failed"] += 1
                            logger.warning("Push to device %s failed: %s", device.id, exc)
                            continue
                        if delivered:
                            counts["sent"] += 1
                        else:
                            dead.add(device.id)
                            db.delete(device)
                            counts["dead_tokens"] += 1
                db.commit()
            except Exception as exc:  # noqa: BLE001 - one user's failure must not stop the others
                db.rollback()
                counts["failed"] += 1
                logger.warning("Reminders for user %s failed: %s", user_id, exc)
    return counts


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    print(dict(run_send_reminders()))
