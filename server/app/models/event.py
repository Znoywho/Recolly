import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey
from app.models.enums import ConflictResolution, EventKind, EventSource, SyncStatus, str_enum

if TYPE_CHECKING:
    from app.models.timetable import Subject
    from app.models.todo import Todo
    from app.models.user import User


class Event(UUIDPrimaryKey, SystemTimeStamp, Base):
    """A calendar block: class, study session, or anything synced with Google Calendar."""

    __tablename__ = "events"
    __table_args__ = (
        CheckConstraint("end_at > start_at", name="end_after_start"),
        UniqueConstraint("user_id", "google_event_id", name="uq_events_user_id_google_event_id"),
        Index("ix_events_user_id_start_at", "user_id", "start_at"),
        Index("ix_events_sync_status", "sync_status"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text)
    location: Mapped[str | None] = mapped_column(String(255))
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    end_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    all_day: Mapped[bool] = mapped_column(Boolean, default=False)
    # RFC 5545 RRULE without the "RRULE:" prefix, e.g. "FREQ=WEEKLY;BYDAY=MO;UNTIL=20261220T000000Z".
    rrule: Mapped[str | None] = mapped_column(String(500))
    kind: Mapped[EventKind] = mapped_column(str_enum(EventKind), default=EventKind.OTHER)
    source: Mapped[EventSource] = mapped_column(str_enum(EventSource), default=EventSource.MANUAL)

    subject_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("subjects.id", ondelete="CASCADE"), index=True
    )
    todo_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("todos.id", ondelete="SET NULL"), index=True
    )

    # Google Calendar sync state.
    google_event_id: Mapped[str | None] = mapped_column(String(1024))
    google_etag: Mapped[str | None] = mapped_column(String(255))
    sync_status: Mapped[SyncStatus] = mapped_column(
        str_enum(SyncStatus), default=SyncStatus.NOT_SYNCED
    )
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="events")
    subject: Mapped["Subject | None"] = relationship(back_populates="events")
    todo: Mapped["Todo | None"] = relationship(back_populates="events")
    conflicts: Mapped[list["SyncConflict"]] = relationship(
        back_populates="event", cascade="all, delete-orphan"
    )


class SyncConflict(UUIDPrimaryKey, Base):
    """Event edited both locally and on Google since the last sync (two-way sync, R45)."""

    __tablename__ = "sync_conflicts"

    event_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("events.id", ondelete="CASCADE"), index=True
    )
    # GoogleEventSnapshot from the contract.
    google_payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    detected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolution: Mapped[ConflictResolution | None] = mapped_column(str_enum(ConflictResolution))

    event: Mapped["Event"] = relationship(back_populates="conflicts")
