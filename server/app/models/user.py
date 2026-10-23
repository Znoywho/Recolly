from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import Date, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base,SystemTimeStamp, UUIDPrimaryKey

# if TYPE_CHECKING:
#     from app.models.event import Event
#     from app.models.health import HealthProfile, SleepLog
#     from app.models.notification import Device, ReminderSettings
#     from app.models.timetable import Subject
#     from app.models.todo import Todo


class User(UUIDPrimaryKey, SystemTimeStamp, Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(320), unique=True)
    display_name: Mapped[str | None] = mapped_column(String(100))
    avatar_url: Mapped[str | None] = mapped_column(String(2048))
    date_of_birth: Mapped[date | None] = mapped_column(Date)
    timezone: Mapped[str] = mapped_column(String(64), server_default="Asia/Ho_Chi_Minh")
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # health_profile: Mapped["HealthProfile | None"] = relationship(
    #     back_populates="user", cascade="all, delete-orphan"
    # )
    # sleep_logs: Mapped[list["SleepLog"]] = relationship(
    #     back_populates="user", cascade="all, delete-orphan"
    # )
    # subjects: Mapped[list["Subject"]] = relationship(
    #     back_populates="user", cascade="all, delete-orphan"
    # )
    # events: Mapped[list["Event"]] = relationship(
    #     back_populates="user", cascade="all, delete-orphan"
    # )
    # todos: Mapped[list["Todo"]] = relationship(
    #     back_populates="user", cascade="all, delete-orphan"
    # )
    # reminder_settings: Mapped["ReminderSettings | None"] = relationship(
    #     back_populates="user", cascade="all, delete-orphan"
    # )
    # devices: Mapped[list["Device"]] = relationship(
    #     back_populates="user", cascade="all, delete-orphan"
    # )
