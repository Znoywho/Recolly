from datetime import datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from app.models.enums import Priority, TodoCategory, TodoStatus
from app.schemas.common import ORMModel, PatchModel

TodoSort = Literal["deadline_at", "-deadline_at", "priority", "-priority", "created_at", "-created_at"]


class TodoInput(BaseModel):
    """`deadline_at` + `estimated_minutes` are needed for S1 to schedule it."""

    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    category: TodoCategory = TodoCategory.OTHER
    priority: Priority = Priority.MEDIUM
    deadline_at: AwareDatetime | None = None
    estimated_minutes: int | None = Field(default=None, ge=1, le=6000)
    difficulty: int | None = Field(default=None, ge=1, le=5,
                                   description="1 easy … 5 hard; hard tasks go to the most alert slots.")
    start_at: AwareDatetime | None = None
    end_at: AwareDatetime | None = None

    @model_validator(mode="after")
    def _check_slot(self) -> Self:
        if self.start_at and self.end_at and self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        return self


class TodoUpdate(PatchModel):
    non_nullable = frozenset({"title", "category", "status", "priority"})

    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    category: TodoCategory | None = None
    status: TodoStatus | None = None
    priority: Priority | None = None
    deadline_at: AwareDatetime | None = None
    estimated_minutes: int | None = Field(default=None, ge=1, le=6000)
    difficulty: int | None = Field(default=None, ge=1, le=5)
    start_at: AwareDatetime | None = None
    end_at: AwareDatetime | None = None


class TodoRead(ORMModel):
    id: UUID
    title: str
    description: str | None
    category: TodoCategory
    status: TodoStatus
    priority: Priority
    deadline_at: datetime | None
    estimated_minutes: int | None
    difficulty: int | None
    start_at: datetime | None
    end_at: datetime | None
    scheduled_minutes: int = Field(
        description="Minutes of study events already linked to this todo (progress vs estimated_minutes).")
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime


class TodoPage(BaseModel):
    items: list[TodoRead]
    next_cursor: str | None


# Voice (V1) shapes, used once a speech model is plugged in.
class TodoDraft(BaseModel):
    """Parsed from speech; not saved until the user confirms with D2."""

    title: str
    description: str | None = None
    category: TodoCategory = TodoCategory.OTHER
    priority: Priority = Priority.MEDIUM
    deadline_at: datetime | None = None
    estimated_minutes: int | None = None
    difficulty: int | None = Field(default=None, ge=1, le=5)


class TranscribeResponse(BaseModel):
    transcript: str
    todo_draft: TodoDraft | None
    parser: Literal["gemini", "rules"]
