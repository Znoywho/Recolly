# import uuid
# from datetime import date, time
# from typing import TYPE_CHECKING
#
# from sqlalchemy import CheckConstraint, Date, ForeignKey, SmallInteger, String, Time
# from sqlalchemy.orm import Mapped, mapped_column, relationship
#
# from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
#
# if TYPE_CHECKING:
#     from app.models.event import Event
#     from app.models.user import User
#
#
# class Subject(UUIDPrimaryKeyMixin, TimestampMixin, Base):
#     """One weekly class slot from the timetable (OCR or manual).
#
#     Saving a subject also creates a recurring Event so it shows on the calendar.
#     """
#
#     __tablename__ = "subjects"
#     __table_args__ = (
#         CheckConstraint("day_of_week BETWEEN 1 AND 7", name="day_of_week_range"),
#         CheckConstraint("end_time > start_time", name="end_after_start"),
#         CheckConstraint("end_date >= start_date", name="end_date_after_start_date"),
#     )
#
#     user_id: Mapped[uuid.UUID] = mapped_column(
#         ForeignKey("users.id", ondelete="CASCADE"), index=True
#     )
#     name: Mapped[str] = mapped_column(String(255))
#     code: Mapped[str | None] = mapped_column(String(50))
#     room: Mapped[str | None] = mapped_column(String(100))
#     lecturer: Mapped[str | None] = mapped_column(String(255))
#     day_of_week: Mapped[int] = mapped_column(SmallInteger)  # 1 = Monday ... 7 = Sunday
#     start_time: Mapped[time] = mapped_column(Time)
#     end_time: Mapped[time] = mapped_column(Time)
#     start_date: Mapped[date] = mapped_column(Date)
#     end_date: Mapped[date] = mapped_column(Date)
#     color: Mapped[str | None] = mapped_column(String(7))  # "#RRGGBB"
#
#     user: Mapped["User"] = relationship(back_populates="subjects")
#     events: Mapped[list["Event"]] = relationship(
#         back_populates="subject", cascade="all, delete-orphan"
#     )
