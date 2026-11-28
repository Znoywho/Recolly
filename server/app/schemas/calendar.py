from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import ConflictPolicy, ConflictResolution, SyncMode
from app.schemas.common import ORMModel, PatchModel
from app.schemas.event import EventRead


class CalendarStatus(ORMModel):
    connected: bool
    google_email: str | None
    calendar_id: str | None
    sync_mode: SyncMode = Field(description="off = paused, push = app → Google, two_way = also pull edits.")
    conflict_policy: ConflictPolicy = Field(description="Who wins when both sides changed the same field.")
    two_way_sync: bool = Field(description="Deprecated: `sync_mode == two_way`.")
    last_synced_at: datetime | None
    pending_count: int
    conflict_count: int


class CalendarSettingsUpdate(PatchModel):
    non_nullable = frozenset({"calendar_id", "sync_mode", "conflict_policy", "two_way_sync"})

    calendar_id: str | None = Field(default=None, min_length=1, max_length=1024,
                                    description="`primary` or a calendar ID the user can write to.")
    sync_mode: SyncMode | None = None
    conflict_policy: ConflictPolicy | None = None
    two_way_sync: bool | None = Field(default=None, description="Deprecated: true = `two_way`, false = `push`.")

    def mode(self) -> SyncMode | None:
        """The requested sync mode; `sync_mode` wins over the deprecated flag."""
        if self.sync_mode is not None:
            return self.sync_mode
        if self.two_way_sync is not None:
            return SyncMode.TWO_WAY if self.two_way_sync else SyncMode.PUSH
        return None


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
