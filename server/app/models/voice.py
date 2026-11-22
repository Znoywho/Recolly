import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Index, SmallInteger, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey
from app.models.enums import JobStatus, str_enum


class VoiceJob(UUIDPrimaryKey, SystemTimeStamp, Base):
    """One voice recording, saved before speech-to-text so a Kaggle outage never loses it.

    The API tries Kaggle at once; if it is down the job stays queued and app.jobs.process_voice retries.
    Rows and audio files are deleted after 7 days. No ORM relationship on User: the FK cascade is enough.
    """

    __tablename__ = "voice_jobs"
    __table_args__ = (Index("ix_voice_jobs_status_created_at", "status", "created_at"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    status: Mapped[JobStatus] = mapped_column(str_enum(JobStatus), default=JobStatus.QUEUED)
    audio_path: Mapped[str] = mapped_column(String(1024))
    # Device "now" at recording time: a retry hours later must still read "tối mai" from that day.
    reference_time: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(SmallInteger, default=0)
    # TranscribeResponse body (without job_id) once succeeded.
    result: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    # VOICE_ASR_UNAVAILABLE | VOICE_BAD_AUDIO
    error_code: Mapped[str | None] = mapped_column(String(64))
