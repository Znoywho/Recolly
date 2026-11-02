import uuid
from datetime import datetime, time
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, SmallInteger, String, Time
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey
from app.models.enums import DevicePlatform, str_enum

if TYPE_CHECKING:
    from app.models.user import User


class ReminderSettings(UUIDPrimaryKey, SystemTimeStamp, Base):
    """Clock windows from the API (`kss_prompt_window`, `quiet_hours`) are stored as start/end columns."""

    __tablename__ = "reminder_settings"
    __table_args__ = (
        CheckConstraint(
            "bedtime_reminder_minutes_before BETWEEN 0 AND 240", name="bedtime_minutes_range"
        ),
        CheckConstraint("kss_prompts_per_day BETWEEN 1 AND 6", name="kss_prompts_range"),
        CheckConstraint(
            "(quiet_hours_start IS NULL) = (quiet_hours_end IS NULL)", name="quiet_hours_both_or_none"
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    bedtime_reminder_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    bedtime_reminder_minutes_before: Mapped[int] = mapped_column(SmallInteger, default=30)
    deadline_reminder_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    deadline_reminder_hours_before: Mapped[list[int]] = mapped_column(
        ARRAY(Integer), default=lambda: [24, 2]
    )
    kss_prompt_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    kss_prompts_per_day: Mapped[int] = mapped_column(SmallInteger, default=4)
    kss_prompt_window_start: Mapped[time] = mapped_column(Time, default=time(8, 0))
    kss_prompt_window_end: Mapped[time] = mapped_column(Time, default=time(23, 0))
    sleep_confirm_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    motivation_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    quiet_hours_start: Mapped[time | None] = mapped_column(Time)
    quiet_hours_end: Mapped[time | None] = mapped_column(Time)

    user: Mapped["User"] = relationship(back_populates="reminder_settings")


class Device(UUIDPrimaryKey, SystemTimeStamp, Base):
    """FCM registration token for push notifications."""

    __tablename__ = "devices"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    fcm_token: Mapped[str] = mapped_column(String(512), unique=True)
    platform: Mapped[DevicePlatform] = mapped_column(
        str_enum(DevicePlatform), default=DevicePlatform.ANDROID
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="devices")
