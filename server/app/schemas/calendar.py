from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import ConflictResolution
from app.schemas.common import ORMModel, PatchModel
from app.schemas.event import EventRead


class CalendarStatus(ORMModel):
    connected: bool
    google_email: str | None
    calendar_id: str | None
    two_way_sync: bool
    last_synced_at: datetime | None
    pending_count: int
    conflict_count: int


class CalendarSettingsUpdate(PatchModel):
    non_nullable = frozenset({"calendar_id", "two_way_sync"})

    calendar_id: str | None = Field(default=None, min_length=1, max_length=1024,
                                    description="`primary` or a calendar ID the user can write to.")
    two_way_sync: bool | None = None


class SyncRequest(BaseModel):
    event_ids: list[UUID] | None = Field(default=None, description="Only these events; null = all pending.")


class SyncResult(BaseModel):
    pushed: int
    pulled: int = Field(description="Changes imported from Google (two-way only).")
    failed: int
    conflicts: int


class GoogleEventSnapshot(ORMModel):
    title: str
    description: str | None
    location: str | None
    start_at: datetime
    end_at: datetime
    updated_at: datetime


class SyncConflictRead(ORMModel):
    id: UUID
    event_id: UUID
    local: EventRead
    google: GoogleEventSnapshot
    detected_at: datetime


class SyncConflictList(BaseModel):
    items: list[SyncConflictRead]


class ConflictResolveRequest(BaseModel):
    keep: ConflictResolution
