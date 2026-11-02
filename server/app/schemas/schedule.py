from datetime import date, datetime, time
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.core.timeutil import ClockTime
from app.schemas.calendar import SyncResult
from app.schemas.common import ORMModel
from app.schemas.event import EventRead
from app.schemas.health import ModelSummary


class ClockWindow(BaseModel):
    """Daily window; `end < start` crosses midnight."""

    start: ClockTime
    end: ClockTime


class ScheduleOptions(BaseModel):
    max_study_minutes_per_day: int = Field(default=240, ge=30, le=720)
    block_minutes: int = Field(default=90, ge=25, le=180)
    min_block_minutes: int = Field(default=45, ge=15, le=180)
    min_break_minutes: int = Field(default=30, ge=0, le=120)
    wake_buffer_minutes: int = Field(default=30, ge=0, le=120)
    bed_buffer_minutes: int = Field(default=60, ge=0, le=180)
    meal_windows: list[ClockWindow] = Field(
        default_factory=lambda: [ClockWindow(start=time(11, 30), end=time(13, 0)),
                                 ClockWindow(start=time(18, 0), end=time(19, 0))],
        max_length=5)
    include_rest_blocks: bool = False
    include_bedtime_blocks: bool = True


class ScheduleGenerateRequest(BaseModel):
    from_: date = Field(alias="from")
    to: date = Field(description="Inclusive. Max 14 days after `from`.")
    todo_ids: list[UUID] | None = None
    options: ScheduleOptions = Field(default_factory=ScheduleOptions)


class ScheduleBlock(ORMModel):
    index: int
    kind: Literal["study", "rest", "bedtime"]
    todo_id: UUID | None
    title: str
    start_at: datetime
    end_at: datetime
    predicted_kss: float | None
    alertness_score: int | None


class UnscheduledTodo(BaseModel):
    todo_id: UUID
    reason: Literal["NOT_ENOUGH_TIME_BEFORE_DEADLINE", "MISSING_DEADLINE", "MISSING_ESTIMATE",
                    "DEADLINE_PASSED", "DAILY_LIMIT_REACHED", "ALREADY_SCHEDULED"]
    missing_minutes: int | None


class ScheduleStats(BaseModel):
    study_minutes: int
    mean_predicted_kss: float | None
    golden_hour_ratio: float
    solve_ms: int


class ScheduleSuggestion(ORMModel):
    suggestion_id: UUID
    expires_at: datetime
    from_: date = Field(serialization_alias="from")
    to: date
    solver_status: Literal["OPTIMAL", "FEASIBLE", "INFEASIBLE", "MODEL_INVALID", "UNKNOWN"]
    blocks: list[ScheduleBlock]
    unscheduled: list[UnscheduledTodo]
    stats: ScheduleStats
    model: ModelSummary


class ScheduleApplyRequest(BaseModel):
    suggestion_id: UUID
    block_indexes: list[int] | None = None
    sync_to_google: bool = False


class ScheduleApplyResult(BaseModel):
    events: list[EventRead]
    sync: SyncResult | None
