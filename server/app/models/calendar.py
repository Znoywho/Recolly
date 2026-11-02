import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey

if TYPE_CHECKING:
    from app.models.user import User


class CalendarConnection(UUIDPrimaryKey, SystemTimeStamp, Base):
    """Google Calendar link for one user (R30, R45). A row exists only while connected."""

    __tablename__ = "calendar_connections"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    google_email: Mapped[str] = mapped_column(String(320))
    calendar_id: Mapped[str] = mapped_column(String(1024), default="primary")
    two_way_sync: Mapped[bool] = mapped_column(Boolean, default=False)
    # Encrypted by the sync service before saving; never store the raw token.
    refresh_token_encrypted: Mapped[str] = mapped_column(Text)
    # Google events.list syncToken for incremental pulls (two-way sync).
    sync_token: Mapped[str | None] = mapped_column(String(1024))
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Push-notification channel behind POST /calendar/webhook.
    channel_id: Mapped[str | None] = mapped_column(String(64), unique=True)
    channel_resource_id: Mapped[str | None] = mapped_column(String(255))
    channel_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="calendar_connection")


class CalendarDeletion(UUIDPrimaryKey, SystemTimeStamp, Base):
    """Google copy of a deleted event, removed from Google on the next sync (E5, T6).

    Needed because the local Event row (and its google_event_id) is gone after the delete.
    """

    __tablename__ = "calendar_deletions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    calendar_id: Mapped[str] = mapped_column(String(1024))
    google_event_id: Mapped[str] = mapped_column(String(1024))

    user: Mapped["User"] = relationship(back_populates="calendar_deletions")
