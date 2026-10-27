import uuid
from datetime import datetime, time
from typing import TYPE_CHECKING, Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Double,
    ForeignKey,
    Index,
    SmallInteger,
    String,
    Time,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey
from app.models.enums import (
    Chronotype,
    ChronotypeSource,
    ChronotypeSpectrum,
    RmeqCategory,
    SleepConcern,
    SleepSource,
    str_enum,
)

if TYPE_CHECKING:
    from app.models.user import User


class HealthProfile(UUIDPrimaryKey, SystemTimeStamp, Base):
    """Baseline sleep habits used to initialise the Process S/C model."""

    __tablename__ = "health_profiles"
    __table_args__ = (
        CheckConstraint("sleep_need_hours BETWEEN 4 AND 12", name="sleep_need_range"),
        CheckConstraint("morning_prep_minutes BETWEEN 0 AND 180", name="morning_prep_range"),
        CheckConstraint("rmeq_score IS NULL OR rmeq_score BETWEEN 4 AND 25", name="rmeq_score_range"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    # Computed results (written by app.service.sleep.chronotype, not by the client).
    chronotype: Mapped[Chronotype] = mapped_column(
        str_enum(Chronotype), default=Chronotype.BEAR
    )
    spectrum: Mapped[ChronotypeSpectrum | None] = mapped_column(str_enum(ChronotypeSpectrum))
    chronotype_source: Mapped[ChronotypeSource] = mapped_column(
        str_enum(ChronotypeSource), default=ChronotypeSource.SELF_REPORT
    )
    sleep_concern: Mapped[SleepConcern] = mapped_column(
        str_enum(SleepConcern), default=SleepConcern.NONE
    )
    rmeq_category: Mapped[RmeqCategory | None] = mapped_column(str_enum(RmeqCategory))
    mctq_result: Mapped[dict[str, Any] | None] = mapped_column(JSONB)

    # User input.
    usual_sleep_time: Mapped[time] = mapped_column(Time)
    usual_wake_time: Mapped[time] = mapped_column(Time)
    sleep_need_hours: Mapped[float] = mapped_column(Double, default=8.0)
    morning_prep_minutes: Mapped[int] = mapped_column(SmallInteger, default=60)
    mctq: Mapped[dict[str, Any] | None] = mapped_column(JSONB)  # MctqAnswers
    rmeq_score: Mapped[int | None] = mapped_column(SmallInteger)
    regular_schedule: Mapped[bool] = mapped_column(Boolean, default=True)
    sleep_quality: Mapped[dict[str, Any] | None] = mapped_column(JSONB)  # SleepQualityAnswers
    screen_tracking_enabled: Mapped[bool] = mapped_column(Boolean, default=False)

    user: Mapped["User"] = relationship(back_populates="health_profile")


class SleepLog(UUIDPrimaryKey, SystemTimeStamp, Base):
    __tablename__ = "sleep_logs"
    __table_args__ = (
        CheckConstraint("wake_at > sleep_at", name="wake_after_sleep"),
        CheckConstraint("wake_at - sleep_at <= interval '16 hours'", name="max_duration"),
        CheckConstraint("quality IS NULL OR quality BETWEEN 1 AND 5", name="quality_range"),
        CheckConstraint("confidence IS NULL OR confidence BETWEEN 0 AND 1", name="confidence_range"),
        Index("ix_sleep_logs_user_id_sleep_at", "user_id", "sleep_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    sleep_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    wake_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    quality: Mapped[int | None] = mapped_column(SmallInteger)
    note: Mapped[str | None] = mapped_column(String(500))
    source: Mapped[SleepSource] = mapped_column(str_enum(SleepSource), default=SleepSource.MANUAL)
    # Always true for manual logs; screen-inferred logs need a user confirm (H5/H9).
    confirmed: Mapped[bool] = mapped_column(Boolean, default=True)
    # Mean HMM P(asleep) over the episode; null for manual logs.
    confidence: Mapped[float | None] = mapped_column(Double)

    user: Mapped["User"] = relationship(back_populates="sleep_logs")

    @property
    def duration_minutes(self) -> int:
        return int((self.wake_at - self.sleep_at).total_seconds() // 60)
