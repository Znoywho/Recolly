from datetime import date, datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from app.core.timeutil import ClockTime
from app.models.enums import (
    Chronotype,
    ChronotypeSource,
    ChronotypeSpectrum,
    RmeqCategory,
    SleepConcern,
    SleepSource,
)
from app.schemas.common import ORMModel, PatchModel
from app.service.sleep.mctq import NightsPerWeek, ProblemDuration

MAX_SLEEP_HOURS = 16


# ─────────────────────────── Chronotype & profile ───────────────────────────

class MctqAnswers(BaseModel):
    """Shortened MCTQ. "Work" = school days; onset = falling asleep, end = waking up."""

    sleep_onset_work: ClockTime
    sleep_end_work: ClockTime
    sleep_onset_free: ClockTime
    sleep_end_free: ClockTime
    work_days: int | None = Field(
        default=None, ge=0, le=7,
        description="School days per week; null = from the timetable (fallback 5). 7 needs rmeq_score.")
    alarm_on_free_days: bool = False


class MctqResult(BaseModel):
    sd_work_hours: float
    sd_free_hours: float
    sd_week_hours: float
    msw: ClockTime
    msf: ClockTime
    msf_sc: ClockTime
    oversleep_corrected: bool
    social_jetlag_hours: float
    chronotype: Chronotype


class SleepQualityAnswers(BaseModel):
    slow_onset_nights: NightsPerWeek
    night_waking_nights: NightsPerWeek
    duration: ProblemDuration | None = None


class ChronotypeAssessmentRequest(BaseModel):
    mctq: MctqAnswers | None = None
    rmeq_score: int | None = Field(default=None, ge=4, le=25)
    regular_schedule: bool = True
    sleep_quality: SleepQualityAnswers | None = None
    school_onset_shift_minutes: int = Field(default=0, ge=-180, le=180)

    @model_validator(mode="after")
    def _not_empty(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("At least one field is required")
        return self


class TypicalWeekDay(BaseModel):
    day: int = Field(ge=0, le=6, description="0 = Monday.")
    wake_time: ClockTime
    sleep_time: ClockTime
    kss_08: float | None
    kss_14: float | None
    kss_22: float | None
    worst_time: ClockTime
    worst_kss: float
    minutes_past_threshold: int
    peak_start: ClockTime | None
    peak_mean_kss: float | None


class TypicalWeekPoint(BaseModel):
    day: int
    time: ClockTime
    asleep: bool
    alertness: float
    kss: float | None


class TypicalWeek(BaseModel):
    phi_hours: float
    school_onset_shift_minutes: int
    days: list[TypicalWeekDay]
    points: list[TypicalWeekPoint]


class ChronotypeAssessment(BaseModel):
    chronotype: Chronotype
    spectrum: ChronotypeSpectrum
    sleep_concern: SleepConcern
    source: ChronotypeSource
    mctq_result: MctqResult | None
    rmeq_category: RmeqCategory | None
    phi_prior_hours: float
    phi_prior_sd_hours: float
    natural_sleep_time: ClockTime
    natural_wake_time: ClockTime
    sleep_shortfall_hours: float | None
    typical_week: TypicalWeek


class HealthProfileInput(BaseModel):
    chronotype: Chronotype | None = Field(
        default=None, description="Self-reported; used only when neither mctq nor rmeq_score is given.")
    usual_sleep_time: ClockTime
    usual_wake_time: ClockTime
    sleep_need_hours: float = Field(default=8.0, ge=4, le=12)
    morning_prep_minutes: int = Field(default=60, ge=0, le=180)
    mctq: MctqAnswers | None = None
    rmeq_score: int | None = Field(default=None, ge=4, le=25)
    regular_schedule: bool = True
    sleep_quality: SleepQualityAnswers | None = None
    screen_tracking_enabled: bool = False


class HealthProfileRead(ORMModel):
    chronotype: Chronotype
    spectrum: ChronotypeSpectrum | None
    sleep_concern: SleepConcern
    chronotype_source: ChronotypeSource
    usual_sleep_time: ClockTime
    usual_wake_time: ClockTime
    sleep_need_hours: float
    morning_prep_minutes: int
    mctq: MctqAnswers | None
    mctq_result: MctqResult | None
    rmeq_score: int | None
    rmeq_category: RmeqCategory | None
    regular_schedule: bool
    sleep_quality: SleepQualityAnswers | None
    screen_tracking_enabled: bool
    updated_at: datetime


# ─────────────────────────── Sleep logs ───────────────────────────

class SleepLogCreate(BaseModel):
    sleep_at: AwareDatetime
    wake_at: AwareDatetime
    quality: int | None = Field(default=None, ge=1, le=5)
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _check_order(self) -> Self:
        if self.wake_at <= self.sleep_at:
            raise ValueError("wake_at must be after sleep_at")
        if (self.wake_at - self.sleep_at).total_seconds() > MAX_SLEEP_HOURS * 3600:
            raise ValueError(f"a sleep log lasts at most {MAX_SLEEP_HOURS} hours")
        return self


class SleepLogUpdate(PatchModel):
    non_nullable = frozenset({"sleep_at", "wake_at"})

    sleep_at: AwareDatetime | None = None
    wake_at: AwareDatetime | None = None
    quality: int | None = Field(default=None, ge=1, le=5)
    note: str | None = Field(default=None, max_length=500)


class SleepLogRead(ORMModel):
    id: UUID
    sleep_at: datetime
    wake_at: datetime
    duration_minutes: int
    quality: int | None
    note: str | None
    source: SleepSource
    confirmed: bool
    confidence: float | None
    created_at: datetime
    updated_at: datetime


class SleepLogList(BaseModel):
    items: list[SleepLogRead]


class DailySleepDebt(BaseModel):
    date: date
    has_data: bool
    slept_minutes: int
    need_minutes: int
    debt_minutes: int
    mid_sleep: ClockTime | None
    is_free_day: bool


class SleepDebtSummary(BaseModel):
    days: int
    total_debt_minutes: int
    average_sleep_minutes: int | None
    social_jetlag_hours: float | None
    current_process_s: float
    daily: list[DailySleepDebt]


# ─────────────────────────── Biorhythm ───────────────────────────

class ModelSummary(BaseModel):
    phi_hours: float
    phi_sd_hours: float
    chi_w_hours: float
    chi_w_sd_hours: float
    personalization_level: Literal["prior_only", "early", "developing", "personalized"]
    kss_days: int


class BiorhythmPoint(ORMModel):
    time: datetime
    asleep: bool
    sleep_state: Literal["observed", "projected", "typical"]
    process_s: float
    process_c: float
    upper_threshold: float
    lower_threshold: float
    alertness: float
    kss_pred: float | None
    kss_lo: float | None
    kss_hi: float | None
    alertness_score: int | None


class BiorhythmWindow(ORMModel):
    start: datetime
    end: datetime
    mean_kss_pred: float
    alertness_score: int


class ProjectedSleep(ORMModel):
    night_of: date
    natural_sleep_at: datetime
    natural_wake_at: datetime
    required_wake_at: datetime | None
    recommended_sleep_at: datetime
    projected_sleep_minutes: int


class Biorhythm(ORMModel):
    date: date
    days: int
    interval_minutes: int
    timezone: str
    model: ModelSummary
    points: list[BiorhythmPoint]
    peak_windows: list[BiorhythmWindow]
    low_windows: list[BiorhythmWindow]
    projected_sleep: list[ProjectedSleep]
    warnings: list[Literal["NO_RECENT_SLEEP_DATA", "UNCONFIRMED_SLEEP_DATA", "PRIOR_ONLY", "TYPICAL_WEEK"]]
