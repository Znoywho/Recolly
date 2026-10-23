# import uuid
# from datetime import datetime, time
# from typing import TYPE_CHECKING
#
# from sqlalchemy import CheckConstraint, DateTime, Float, ForeignKey, Index, SmallInteger, Text, Time
# from sqlalchemy.orm import Mapped, mapped_column, relationship
#
# from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
# from app.models.enums import Chronotype, str_enum
#
# if TYPE_CHECKING:
#     from app.models.user import User
#
#
# class HealthProfile(UUIDPrimaryKeyMixin, TimestampMixin, Base):
#     """Baseline sleep habits used to initialise the Process S/C model."""
#
#     __tablename__ = "health_profiles"
#     __table_args__ = (
#         CheckConstraint("sleep_need_hours BETWEEN 4 AND 12", name="sleep_need_range"),
#     )
#
#     user_id: Mapped[uuid.UUID] = mapped_column(
#         ForeignKey("users.id", ondelete="CASCADE"), unique=True
#     )
#     chronotype: Mapped[Chronotype] = mapped_column(
#         str_enum(Chronotype), default=Chronotype.BEAR
#     )
#     usual_sleep_time: Mapped[time] = mapped_column(Time)
#     usual_wake_time: Mapped[time] = mapped_column(Time)
#     sleep_need_hours: Mapped[float] = mapped_column(Float, default=8.0)
#
#     user: Mapped["User"] = relationship(back_populates="health_profile")
#
#
# class SleepLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
#     __tablename__ = "sleep_logs"
#     __table_args__ = (
#         CheckConstraint("wake_at > sleep_at", name="wake_after_sleep"),
#         CheckConstraint("quality IS NULL OR quality BETWEEN 1 AND 5", name="quality_range"),
#         Index("ix_sleep_logs_user_id_sleep_at", "user_id", "sleep_at"),
#     )
#
#     user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
#     sleep_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
#     wake_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
#     quality: Mapped[int | None] = mapped_column(SmallInteger)
#     note: Mapped[str | None] = mapped_column(Text)
#
#     user: Mapped["User"] = relationship(back_populates="sleep_logs")
#
#     @property
#     def duration_minutes(self) -> int:
#         return int((self.wake_at - self.sleep_at).total_seconds() // 60)
