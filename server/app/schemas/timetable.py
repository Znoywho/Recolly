from datetime import date, time
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.models.enums import JobStatus
from app.schemas.common import ORMModel

HEX_COLOR = r"^#[0-9A-Fa-f]{6}$"


class SubjectBase(BaseModel):
    name: str = Field(max_length=255)
    code: str | None = Field(default=None, max_length=50)
    room: str | None = Field(default=None, max_length=100)
    lecturer: str | None = Field(default=None, max_length=255)
    day_of_week: int = Field(ge=1, le=7, description="1 = Monday ... 7 = Sunday")
    start_time: time
    end_time: time
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def check_ranges(self) -> "SubjectBase":
        if self.end_time <= self.start_time:
            raise ValueError("end_time must be after start_time")
        if self.end_date < self.start_date:
            raise ValueError("end_date must not be before start_date")
        return self


class SubjectCreate(SubjectBase):
    color: str | None = Field(default=None, pattern=HEX_COLOR)


class SubjectBulkCreate(BaseModel):
    subjects: list[SubjectCreate] = Field(min_length=1)
    replace_existing: bool = False


class SubjectUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=255)
    code: str | None = Field(default=None, max_length=50)
    room: str | None = Field(default=None, max_length=100)
    lecturer: str | None = Field(default=None, max_length=255)
    day_of_week: int | None = Field(default=None, ge=1, le=7)
    start_time: time | None = None
    end_time: time | None = None
    start_date: date | None = None
    end_date: date | None = None
    color: str | None = Field(default=None, pattern=HEX_COLOR)


class SubjectRead(SubjectBase, ORMModel):
    id: UUID
    color: str | None


class OcrSubject(SubjectBase):
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
