from datetime import date, datetime
from typing import Self
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.core.timeutil import ClockTime
from app.models.enums import JobStatus
from app.schemas.common import ORMModel, PatchModel

HEX_COLOR = r"^#[0-9A-Fa-f]{6}$"


class SubjectFields(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    code: str | None = Field(default=None, max_length=50)
    room: str | None = Field(default=None, max_length=100)
    lecturer: str | None = Field(default=None, max_length=255)
    day_of_week: int = Field(ge=1, le=7, description="1 = Monday ... 7 = Sunday")
    start_time: ClockTime
    end_time: ClockTime
    start_date: date = Field(description="First week of the course.")
    end_date: date = Field(description="Last week of the course.")

    @model_validator(mode="after")
    def _check_ranges(self) -> Self:
        if self.end_time <= self.start_time:
            raise ValueError("end_time must be after start_time")
        if self.end_date < self.start_date:
            raise ValueError("end_date must not be before start_date")
        return self


class SubjectInput(SubjectFields):
    color: str | None = Field(default=None, pattern=HEX_COLOR)


class SubjectBulkCreate(BaseModel):
    subjects: list[SubjectInput] = Field(min_length=1, max_length=100)
    replace_existing: bool = False


class SubjectUpdate(PatchModel):
    non_nullable = frozenset({"name", "day_of_week", "start_time", "end_time", "start_date", "end_date"})

    name: str | None = Field(default=None, min_length=1, max_length=255)
    code: str | None = Field(default=None, max_length=50)
    room: str | None = Field(default=None, max_length=100)
    lecturer: str | None = Field(default=None, max_length=255)
    day_of_week: int | None = Field(default=None, ge=1, le=7)
    start_time: ClockTime | None = None
    end_time: ClockTime | None = None
    start_date: date | None = None
    end_date: date | None = None
    color: str | None = Field(default=None, pattern=HEX_COLOR)


class SubjectRead(ORMModel):
    id: UUID
    name: str
    code: str | None
    room: str | None
    lecturer: str | None
    day_of_week: int
    start_time: ClockTime
    end_time: ClockTime
    start_date: date
    end_date: date
    color: str | None
    created_at: datetime
    updated_at: datetime


class SubjectList(BaseModel):
    items: list[SubjectRead]


# OCR (T1/T2) shapes, used once a model provider is plugged in.
class OcrSubject(SubjectFields):
    confidence: float = Field(ge=0, le=1)


class OcrResult(BaseModel):
    subjects: list[OcrSubject]


class OcrJobCreated(BaseModel):
    job_id: UUID
    status: JobStatus


class OcrJobRead(BaseModel):
    job_id: UUID
    status: JobStatus
    error: str | None = None
    result: OcrResult | None = None
    created_at: datetime
