"""Send due bedtime / deadline reminders (R39) to every registered device.

Run every 5 minutes (cron now, a Kubernetes CronJob when deployed):
    python -m app.jobs.send_reminders
Each run covers the window [now − RUN_EVERY, now).
shortcut: a missed run skips its reminders and an extra run in the same window repeats them;
upgrade to a Redis SET NX key per (user, type, ref, trigger) once Redis is merged (plan A4).
"""

import logging
from collections import Counter
from datetime import datetime, timedelta

from sqlalchemy import select

from app.core.timeutil import now_utc
from app.db.session import SessionLocal
from app.models.notification import Device
from app.models.user import User
from app.service.push import FcmSender, LogSender, get_push_sender
from app.service.reminders import due_reminders

logger = logging.getLogger(__name__)

RUN_EVERY = timedelta(minutes=5)


def run_send_reminders(now: datetime | None = None, sender: FcmSender | LogSender | None = None) -> Counter:
    """Send what fell due in the last RUN_EVERY to each user's devices; one failing user skips only itself."""
    now = now or now_utc()
    sender = sender or get_push_sender()
    with SessionLocal() as db:
        user_ids = db.scalars(select(Device.user_id).distinct()).all()
    counts: Counter = Counter()
    for user_id in user_ids:
        with SessionLocal() as db:
            try:
                user = db.get(User, user_id)
                dead: set = set()
                for payload in due_reminders(db, user, now - RUN_EVERY, now):
                    for device in user.devices:
                        if device.id in dead:
                            continue
                        if sender.send(device.fcm_token, payload):
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
