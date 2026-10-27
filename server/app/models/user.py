from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import Date, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey
from app.models.health import HealthProfile
from app.models.timetable import Subject


class User(UUIDPrimaryKey, SystemTimeStamp, Base):
    __tablename__ = "users"

    # Google account ID ("sub" claim); stable even if the user changes their email.
    google_sub: Mapped[str] = mapped_column(String(255), unique=True)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    display_name: Mapped[str | None] = mapped_column(String(100))
    avatar_url: Mapped[str | None] = mapped_column(String(2048))
    date_of_birth: Mapped[date | None] = mapped_column(Date)
    timezone: Mapped[str] = mapped_column(String(64), server_default="Asia/Ho_Chi_Minh")
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    health_profile: Mapped["HealthProfile | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    sleep_logs: Mapped[list["SleepLog"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    subjects: Mapped[list["Subject"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    events: Mapped[list["Event"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    todos: Mapped[list["Todo"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    ocr_jobs: Mapped[list["OcrJob"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    reminder_settings: Mapped["ReminderSettings | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    devices: Mapped[list["Device"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    calendar_connection: Mapped["CalendarConnection | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )

    # Derived fields of the User response (see docs/openapi.yaml).
    @property
    def onboarding_completed(self) -> bool:
        return self.health_profile is not None

    @property
    def google_calendar_connected(self) -> bool:
        return self.calendar_connection is not None
