from datetime import date, datetime

from app.schemas.common import ORMModel
from app.schemas.event import EventRead
from app.schemas.health import BiorhythmWindow, ModelSummary, ProjectedSleep, SleepLogRead
from app.schemas.todo import TodoRead


class NowState(ORMModel):
    time: datetime
    asleep: bool
    process_s: float
    process_c: float
    kss_pred: float | None
    kss_lo: float | None
    kss_hi: float | None
    alertness_score: int | None


class HomeOverview(ORMModel):
    date: date
    now: NowState
    next_peak_window: BiorhythmWindow | None
    tonight: ProjectedSleep | None
    today_events: list[EventRead]
    upcoming_todos: list[TodoRead]
    sleep_debt_7d_minutes: int
    last_night: SleepLogRead | None
    needs_sleep_confirmation: bool
    kss_checkin_due: bool
    model: ModelSummary
