"""Retry saved voice recordings that waited for Kaggle, push "voice_ready", delete week-old recordings.

Run once:            python -m app.jobs.process_voice
Run every minute (the `voice-worker` service in docker-compose.yml):
                     python -m app.jobs.process_voice --loop
Jobs are claimed with SELECT … FOR UPDATE SKIP LOCKED, so two workers (or a worker and the API) never
process the same recording twice.
"""

import logging
import sys
import time
from collections import Counter
from datetime import datetime, timedelta

from sqlalchemy import or_, select, update

from app.core.timeutil import now_utc
from app.db.session import SessionLocal
from app.models.enums import JobStatus
from app.models.notification import Device
from app.models.voice import VoiceJob
from app.service.push import FcmSender, LogSender, get_push_sender
from app.service.voice.voice_jobs import delete_expired, process_job

RUN_EVERY = timedelta(minutes=1)
BATCH_SIZE = 5               # Kaggle has one GPU for speech; a few files per minute is plenty
STALE_PROCESSING = timedelta(minutes=10)  # a "processing" job this old lost its process (crash, restart)
GIVE_UP_AFTER = timedelta(hours=24)

logger = logging.getLogger(__name__)


def give_up_old_jobs(db, now: datetime) -> int:
    """Fail jobs still waiting after GIVE_UP_AFTER, so the app stops polling them."""
    result = db.execute(update(VoiceJob)
                        .where(VoiceJob.status.in_([JobStatus.QUEUED, JobStatus.PROCESSING]),
                               VoiceJob.created_at < now - GIVE_UP_AFTER)
                        .values(status=JobStatus.FAILED, error_code="VOICE_ASR_UNAVAILABLE"))
    db.commit()
    return result.rowcount


def claim_jobs(db, now: datetime) -> list:
    """Mark up to BATCH_SIZE waiting (or crashed) jobs as processing and return their ids, oldest first."""
    waiting = or_(VoiceJob.status == JobStatus.QUEUED,
                  (VoiceJob.status == JobStatus.PROCESSING) & (VoiceJob.updated_at < now - STALE_PROCESSING))
    job_ids = db.scalars(select(VoiceJob.id).where(waiting).order_by(VoiceJob.created_at)
                         .limit(BATCH_SIZE).with_for_update(skip_locked=True)).all()
    if job_ids:
        db.execute(update(VoiceJob).where(VoiceJob.id.in_(job_ids)).values(status=JobStatus.PROCESSING))
    db.commit()
    return job_ids


def notify_voice_ready(db, job: VoiceJob, sender: FcmSender | LogSender) -> None:
    """Tell the user's devices the draft is ready; a failing device must not block the others."""
    draft = job.result.get("todo_draft") or {}
    payload = {"type": "voice_ready", "title": "Đã xử lý ghi âm",
               "body": draft.get("title") or "Mở Recolly để xem ghi chú giọng nói", "job_id": str(job.id)}
    for device in db.scalars(select(Device).where(Device.user_id == job.user_id)):
        try:
            sender.send(device.fcm_token, payload)
        except Exception as exc:  # noqa: BLE001 - dead tokens are cleaned up by send_reminders
            logger.warning("voice_ready push to device %s failed: %s", device.id, exc)


def run_process_voice(now: datetime | None = None, sender: FcmSender | LogSender | None = None) -> Counter:
    """One worker pass: give up, retry, notify, clean up. Returns counts for the log."""
    now = now or now_utc()
    sender = sender or get_push_sender()
    counts: Counter = Counter()
    with SessionLocal() as db:
        counts["gave_up"] = give_up_old_jobs(db, now)
        job_ids = claim_jobs(db, now)
    for job_id in job_ids:
        with SessionLocal() as db:
            job = db.get(VoiceJob, job_id)
            try:
                process_job(db, job)
            except Exception as exc:  # noqa: BLE001 - one broken job must not stop the others
                db.rollback()
                job.status = JobStatus.QUEUED  # retried next minute until GIVE_UP_AFTER
                db.commit()
                logger.warning("Voice job %s crashed: %s", job_id, exc)
            counts[str(job.status)] += 1
            if job.status == JobStatus.SUCCEEDED:
                notify_voice_ready(db, job, sender)
    with SessionLocal() as db:
        counts["deleted"] = delete_expired(db, now)
    return counts


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    if "--loop" not in sys.argv:
        logger.info("Voice run: %s", dict(run_process_voice()))
        sys.exit()
    period = RUN_EVERY.total_seconds()
    while True:
        time.sleep(period - time.time() % period)
        logger.info("Voice run: %s", dict(run_process_voice()))
