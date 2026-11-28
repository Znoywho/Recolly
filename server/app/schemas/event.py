from datetime import datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from app.models.enums import EventKind, EventSource, SyncStatus
from app.schemas.common import ORMModel, PatchModel


class EventInput(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    location: str | None = Field(default=None, max_length=255)
    start_at: AwareDatetime
    end_at: AwareDatetime
    all_day: bool = False
    rrule: str | None = Field(
        default=None,
        max_length=500,
        description='RFC 5545 RRULE without the "RRULE:" prefix',
        examples=["FREQ=WEEKLY;BYDAY=MO;UNTIL=20261220T000000Z"],
    )
    kind: EventKind = Field(default=EventKind.OTHER,
                            description="`class` is reserved for timetable events.")
    todo_id: UUID | None = None

    @model_validator(mode="after")
    def _check(self) -> Self:
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        if self.kind is EventKind.CLASS:
            raise ValueError("kind `class` is reserved for timetable events")
        return self


class EventUpdate(PatchModel):
    non_nullable = frozenset({"title", "start_at", "end_at", "all_day", "kind"})

    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    location: str | None = Field(default=None, max_length=255)
    start_at: AwareDatetime | None = None
    end_at: AwareDatetime | None = None
    all_day: bool | None = None
    rrule: str | None = Field(default=None, max_length=500)
    kind: EventKind | None = None
    todo_id: UUID | None = None


class EventRead(ORMModel):
    id: UUID
    title: str
    description: str | None
    location: str | None
    start_at: datetime = Field(description="For expanded instances, the instance start.")
    end_at: datetime
    all_day: bool
    rrule: str | None
    kind: EventKind
    source: EventSource
    subject_id: UUID | None
    todo_id: UUID | None
    google_event_id: str | None
    sync_status: SyncStatus
    occurrence_start: datetime | None = Field(
        default=None, description="Set only on recurring instances returned by E1.")
    created_at: datetime
    updated_at: datetime


class ClashRead(ORMModel):
    """Something at the same time as the saved event."""

    title: str
    start_at: datetime
    end_at: datetime
    event_id: UUID | None = Field(description="Null for a busy time on the user's Google calendar.")
    kind: EventKind | None
    source: Literal["recolly", "google"]
    movable: bool = Field(description="A CP-SAT block that could not be moved (e.g. no sleep profile).")


class EventSaved(EventRead):
    """E2/E4 answer: the event plus what it overlaps after CP-SAT blocks made room."""

    clashes: list[ClashRead] = Field(default_factory=list, description="Fixed things still at the same time: "
                                     "the app asks the user to keep both, move or drop.")
    rescheduled: list[EventRead] = Field(default_factory=list,
                                         description="CP-SAT study blocks moved out of the way (new events).")


class EventList(BaseModel):
    items: list[EventRead]
