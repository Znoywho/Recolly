from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.models.enums import Chronotype
from app.schemas.common import ORMModel


class HealthProfileBase(BaseModel):
    chronotype: Chronotype = Chronotype.BEAR
    usual_sleep_time: time
    usual_wake_time: time
    sleep_need_hours: float = Field(default=8.0, ge=4, le=12)


class HealthProfileUpsert(HealthProfileBase):
    pass


class HealthProfileRead(HealthProfileBase, ORMModel):
    pass


class SleepLogCreate(BaseModel):
    sleep_at: datetime
    wake_at: datetime
    quality: int | None = Field(default=None, ge=1, le=5)
    note: str | None = None

    @model_validator(mode="after")
    def check_order(self) -> "SleepLogCreate":
        if self.wake_at <= self.sleep_at:
            raise ValueError("wake_at must be after sleep_at")
        return self


class SleepLogUpdate(BaseModel):
    sleep_at: datetime | None = None
    wake_at: datetime | None = None
    quality: int | None = Field(default=None, ge=1, le=5)
    note: str | None = None


class SleepLogRead(ORMModel):
    id: UUID
    sleep_at: datetime
    wake_at: datetime
    duration_minutes: int
    quality: int | None
    note: str | None


class DailySleepDebt(BaseModel):
    date: date
    slept_minutes: int
    need_minutes: int
    debt_minutes: int


class SleepDebtRead(BaseModel):
    days: int
    total_debt_minutes: int
    daily: list[DailySleepDebt]


class BiorhythmPoint(BaseModel):
    time: datetime
    process_s: float = Field(ge=0, le=1)
    process_c: float = Field(ge=0, le=1)
    alertness: float = Field(ge=0, le=1)


class TimeWindow(BaseModel):
    start: datetime
    end: datetime


class BiorhythmRead(BaseModel):
    date: date
    interval_minutes: int
    points: list[BiorhythmPoint]
    peak_windows: list[TimeWindow]
    low_windows: list[TimeWindow]
