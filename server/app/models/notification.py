# import uuid
# from datetime import datetime, time
# from typing import TYPE_CHECKING
#
# from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, SmallInteger, String, Time
# from sqlalchemy.dialects.postgresql import ARRAY
# from sqlalchemy.orm import Mapped, mapped_column, relationship
#
# from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
# from app.models.enums import DevicePlatform, str_enum
#
# if TYPE_CHECKING:
#     from app.models.user import User
#
#
# class ReminderSettings(UUIDPrimaryKeyMixin, TimestampMixin, Base):
#     __tablename__ = "reminder_settings"
#
#     user_id: Mapped[uuid.UUID] = mapped_column(
#         ForeignKey("users.id", ondelete="CASCADE"), unique=True
#     )
#     bedtime_reminder_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
#     bedtime_reminder_minutes_before: Mapped[int] = mapped_column(SmallInteger, default=30)
#     deadline_reminder_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
#     deadline_reminder_hours_before: Mapped[list[int]] = mapped_column(
#         ARRAY(Integer), default=lambda: [24, 2]
#     )
#     motivation_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
#     quiet_hours_start: Mapped[time | None] = mapped_column(Time)
#     quiet_hours_end: Mapped[time | None] = mapped_column(Time)
#
#     user: Mapped["User"] = relationship(back_populates="reminder_settings")
#
#
# class Device(UUIDPrimaryKeyMixin, TimestampMixin, Base):
#     """FCM registration token for push notifications."""
#
#     __tablename__ = "devices"
#
#     user_id: Mapped[uuid.UUID] = mapped_column(
#         ForeignKey("users.id", ondelete="CASCADE"), index=True
#     )
#     fcm_token: Mapped[str] = mapped_column(String(512), unique=True)
#     platform: Mapped[DevicePlatform] = mapped_column(
#         str_enum(DevicePlatform), default=DevicePlatform.ANDROID
#     )
#     last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
#
#     user: Mapped["User"] = relationship(back_populates="devices")
