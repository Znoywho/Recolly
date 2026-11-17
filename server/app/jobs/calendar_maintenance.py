"""Daily Google Calendar upkeep for every two-way user: keep push channels alive, pull as fallback.

Run once a day (cron now, a Kubernetes CronJob when deployed):
    python -m app.jobs.calendar_maintenance
Costs about 1 events.watch per user per week, plus 1 pull per day for users without a live channel.
"""

import logging
from collections import Counter

from sqlalchemy import select

from app.core.errors import ApiError
from app.db.session import SessionLocal
from app.models.calendar import CalendarConnection
from app.models.user import User
from app.service import calendar_sync
from app.service.google import GoogleClient, GoogleError, get_google_client

logger = logging.getLogger(__name__)


def run_calendar_maintenance(google: GoogleClient | None = None) -> Counter:
    """Run daily_maintenance for each two-way user in its own transaction; one failure skips only that user."""
    google = google or get_google_client()
    with SessionLocal() as db:
        user_ids = db.scalars(select(CalendarConnection.user_id)
                              .where(CalendarConnection.two_way_sync.is_(True))).all()
    counts: Counter = Counter()
    for user_id in user_ids:
        with SessionLocal() as db:
            try:
                pulled = calendar_sync.daily_maintenance(db, db.get(User, user_id), google)
                db.commit()
                counts["pulled" if pulled else "channel_ok"] += 1
            except (GoogleError, ApiError) as exc:
                db.rollback()
                counts["failed"] += 1
                logger.warning("Calendar maintenance for user %s failed: %s", user_id, exc)
    return counts


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    print(dict(run_calendar_maintenance()))
