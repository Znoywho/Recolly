from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.models.enums import Priority, TodoCategory, TodoStatus
from app.schemas.common import ORMModel


class TodoBase(BaseModel):
    title: str = Field(max_length=255)
    description: str | None = None
    category: TodoCategory = TodoCategory.OTHER
    priority: Priority = Priority.MEDIUM
    deadline_at: datetime | None = None
    estimated_minutes: int | None = Field(default=None, gt=0)
    difficulty: int | None = Field(default=None, ge=1, le=5)
    start_at: datetime | None = None
    end_at: datetime | None = None


class TodoCreate(TodoBase):
    @model_validator(mode="after")
    def check_order(self) -> "TodoCreate":
        if self.start_at and self.end_at and self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        return self


class TodoUpdate(BaseModel):
    title: str | None = Field(default=None, max_length=255)
    description: str | None = None
    category: TodoCategory | None = None
    status: TodoStatus | None = None
    priority: Priority | None = None
    deadline_at: datetime | None = None
    estimated_minutes: int | None = Field(default=None, gt=0)
    difficulty: int | None = Field(default=None, ge=1, le=5)
    start_at: datetime | None = None
    end_at: datetime | None = None


class TodoRead(TodoBase, ORMModel):
    id: UUID
    status: TodoStatus
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime


class TodoDraft(BaseModel):
    """Todo parsed from a voice transcript; not saved until the user confirms (POST /todos)."""

    title: str
    category: TodoCategory = TodoCategory.OTHER
    priority: Priority = Priority.MEDIUM
    deadline_at: datetime | None = None
    estimated_minutes: int | None = None


class TranscribeResponse(BaseModel):
    transcript: str
    todo_draft: TodoDraft | None
