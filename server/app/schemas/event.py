from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.models.enums import EventSource, SyncStatus
from app.schemas.common import ORMModel


class EventBase(BaseModel):
    title: str = Field(max_length=255)
    description: str | None = None
    location: str | None = Field(default=None, max_length=255)
    start_at: datetime
    end_at: datetime
    all_day: bool = False
    rrule: str | None = Field(
        default=None,
        max_length=500,
        description='RFC 5545 RRULE without "RRULE:" prefix',
        examples=["FREQ=WEEKLY;BYDAY=MO;UNTIL=20261220T000000Z"],
    )
    todo_id: UUID | None = None


class EventCreate(EventBase):
    @model_validator(mode="after")
    def check_order(self) -> "EventCreate":
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        return self


class EventUpdate(BaseModel):
    title: str | None = Field(default=None, max_length=255)
    description: str | None = None
    location: str | None = Field(default=None, max_length=255)
    start_at: datetime | None = None
    end_at: datetime | None = None
    all_day: bool | None = None
    rrule: str | None = Field(default=None, max_length=500)
    todo_id: UUID | None = None


class EventRead(EventBase, ORMModel):
    id: UUID
    source: EventSource
    subject_id: UUID | None
    google_event_id: str | None
    sync_status: SyncStatus
    # Set only on expanded recurring instances returned by GET /events.
    occurrence_start: datetime | None = None
    created_at: datetime
    updated_at: datetime
