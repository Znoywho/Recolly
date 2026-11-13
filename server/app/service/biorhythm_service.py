"""Connects the sleep model to the database: profile -> phi, timetable -> school days and
alarms, sleep logs -> observed nights (H7, H8, S1, O1)."""

from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import not_found
from app.core.timeutil import clock_from_hours, day_start, hours, now_utc, today
from app.models.enums import ChronotypeSource, EventKind
from app.models.event import Event
from app.models.health import HealthProfile, SleepLog
from app.models.timetable import Subject
from app.models.user import User
from app.service.event_service import occurrences
from app.service.sleep.chronotype import Animal
from app.service.sleep.mctq import (
    ANIMAL_MID_SLEEP,
    PHI_SD_UNCERTAIN_HOURS,
    MctqAnswers,
    NightsPerWeek,
    ProblemDuration,
    SleepQualityAnswers,
    assess,
)
from app.service.sleep.debt import sleep_need
from app.service.sleep.timeline import Timeline
from app.service.sleep.two_process import Params, circular_diff_hours, circular_mean_hours, phi_from_mid_sleep
from app.service.sleep.typical_week import WeekSchedule, schedule_from_mctq

CHI_W_PRIOR = (18.2, 2.5)  # population prior of chi_w (mean, SD), no personalisation yet
DEFAULT_SCHOOL_DAYS = 5


def require_profile(user: User) -> HealthProfile:
    if user.health_profile is None:
        raise not_found("health_profile")
    return user.health_profile


def timetable_weekdays(db: Session, user: User) -> frozenset[int]:
    """Weekdays (0 = Monday) with at least one class."""
    days = db.scalars(select(Subject.day_of_week).where(Subject.user_id == user.id).distinct()).all()
    return frozenset(d - 1 for d in days)


def school_days(db: Session, user: User, work_days: int | None) -> frozenset[int]:
    """School weekdays for the typical week: the timetable if it agrees, else Monday onwards."""
    from_timetable = timetable_weekdays(db, user)
    count = len(from_timetable) if work_days is None and from_timetable else work_days
    if count is None:
        count = DEFAULT_SCHOOL_DAYS
    if from_timetable and len(from_timetable) == count:
        return from_timetable
    return frozenset(range(count))


def mctq_answers(data: dict[str, Any] | None, days: frozenset[int]) -> MctqAnswers | None:
    """Contract-shaped MctqAnswers (HH:MM strings or times) -> service dataclass."""
    if not data:
        return None

    def clock(value: Any) -> float:
        if isinstance(value, str):
            hour, minute = value.split(":")
            return int(hour) + int(minute) / 60
        return hours(value)

    work_days = data.get("work_days")
    return MctqAnswers(clock(data["sleep_onset_work"]), clock(data["sleep_end_work"]),
                       clock(data["sleep_onset_free"]), clock(data["sleep_end_free"]),
                       work_days=len(days) if work_days is None else work_days,
                       alarm_on_free_days=bool(data.get("alarm_on_free_days", False)))


def quality_answers(data: dict[str, Any] | None) -> SleepQualityAnswers | None:
    if not data:
        return None
    duration = data.get("duration")
    return SleepQualityAnswers(NightsPerWeek(data["slow_onset_nights"]),
                               NightsPerWeek(data["night_waking_nights"]),
                               ProblemDuration(duration) if duration else None)


def phi_prior(db: Session, user: User, profile: HealthProfile) -> tuple[float, float]:
    """(phi, SD): from the questionnaire, else the self-reported animal."""
    if profile.chronotype_source in (ChronotypeSource.MCTQ, ChronotypeSource.RMEQ):
        days = school_days(db, user, (profile.mctq or {}).get("work_days"))
        try:
            a = assess(mctq_answers(profile.mctq, days), profile.rmeq_score, profile.regular_schedule,
                       quality_answers(profile.sleep_quality))
            return a.phi_hours, a.phi_sd_hours
        except ValueError:
            pass
    return phi_from_mid_sleep(ANIMAL_MID_SLEEP[Animal(profile.chronotype)]), PHI_SD_UNCERTAIN_HOURS


def week_schedule(db: Session, user: User, profile: HealthProfile) -> WeekSchedule:
    """Questionnaire school/free nights if answered, else the usual sleep times every night."""
    days = school_days(db, user, (profile.mctq or {}).get("work_days"))
    answers = mctq_answers(profile.mctq, days)
    if answers is not None:
        return schedule_from_mctq(answers, days)
    usual = (hours(profile.usual_sleep_time), hours(profile.usual_wake_time))
    return WeekSchedule(usual, usual, days)


def first_classes(db: Session, user: User, start: datetime, end: datetime,
                  tz: ZoneInfo) -> dict[date, datetime]:
    events = db.scalars(select(Event).where(Event.user_id == user.id, Event.kind == EventKind.CLASS,
                                            Event.start_at < end)).all()
    first: dict[date, datetime] = {}
    for occ in occurrences(events, start, end, tz):
        day = occ.start.astimezone(tz).date()
        if day not in first:
            first[day] = occ.start.astimezone(tz)
    return first


def confirmed_logs(db: Session, user: User, start: datetime, end: datetime) -> list[SleepLog]:
    return list(db.scalars(select(SleepLog).where(
        SleepLog.user_id == user.id, SleepLog.confirmed.is_(True),
        SleepLog.wake_at > start, SleepLog.sleep_at < end).order_by(SleepLog.sleep_at)).all())


def has_sleep_logs(db: Session, user: User) -> bool:
    return db.scalar(select(SleepLog.id).where(SleepLog.user_id == user.id).limit(1)) is not None


def timeline_for(db: Session, user: User, profile: HealthProfile, first_day: date, days: int,
                 now: datetime | None = None) -> Timeline:
    tz = ZoneInfo(user.timezone)
    phi, _ = phi_prior(db, user, profile)
    start = datetime.combine(first_day - timedelta(days=8), datetime.min.time(), tz)
    end = datetime.combine(first_day + timedelta(days=days + 2), datetime.min.time(), tz)
    logs = [(log.sleep_at, log.wake_at) for log in confirmed_logs(db, user, start, end)]
    return Timeline.build(
        tz=tz, first_day=first_day, days=days, now=now or now_utc(),
        params=Params(phi=phi, chi_w=CHI_W_PRIOR[0]),
        schedule=week_schedule(db, user, profile), logs=logs,
        first_class=first_classes(db, user, start, end, tz),
        prep=timedelta(minutes=profile.morning_prep_minutes),
        sleep_need_hours=profile.sleep_need_hours,
    )


def _mid_sleep(log: SleepLog, tz: ZoneInfo) -> float:
    start = log.sleep_at.astimezone(tz)
    return (hours(start.time()) + (log.wake_at - log.sleep_at).total_seconds() / 7200) % 24


def debt_summary(db: Session, user: User, profile: HealthProfile, days: int) -> dict[str, Any]:
    """H7: need − slept per wake-up date (plain arithmetic, the 2PM under-estimates chronic loss),
    social jetlag from real logs and the sleep pressure right now."""
    tz = ZoneInfo(user.timezone)
    last = today(tz)
    first = last - timedelta(days=days - 1)
    start, end = day_start(first, tz), day_start(last + timedelta(days=1), tz)
    logs = confirmed_logs(db, user, start - timedelta(days=1), end)
    need = round(sleep_need(profile.sleep_need_hours) * 60)
    class_days = set(first_classes(db, user, start, end, tz))

    daily, mids = [], {True: [], False: []}
    for offset in range(days):
        day = first + timedelta(days=offset)
        ending = [log for log in logs if log.wake_at.astimezone(tz).date() == day]
        main = max(ending, key=lambda log: log.duration_minutes, default=None)
        free = day not in class_days
        if main is not None:
            mids[free].append(_mid_sleep(main, tz))
        slept = sum(log.duration_minutes for log in ending)
        daily.append({
            "date": day,
            "has_data": bool(ending),
            "slept_minutes": slept,
            "need_minutes": need,
            "debt_minutes": need - slept if ending else 0,
            "mid_sleep": clock_from_hours(_mid_sleep(main, tz)) if main else None,
            "is_free_day": free,
        })
    with_data = [d for d in daily if d["has_data"]]
    jetlag = None
    if mids[True] and mids[False]:
        jetlag = round(abs(circular_diff_hours(circular_mean_hours(mids[True]),
                                               circular_mean_hours(mids[False]))), 2)
    timeline = timeline_for(db, user, profile, last, 1)
    return {
        "days": days,
        "total_debt_minutes": max(0, sum(d["debt_minutes"] for d in with_data)),
        "average_sleep_minutes": round(sum(d["slept_minutes"] for d in with_data) / len(with_data))
        if with_data else None,
        "social_jetlag_hours": jetlag,
        "current_process_s": round(timeline.at(now_utc()).process_s, 3),
        "daily": daily,
    }


def model_summary(db: Session, user: User, profile: HealthProfile) -> dict[str, Any]:
    """Prior-only ModelSummary: KSS check-ins (Bayes) come after the course project."""
    phi, phi_sd = phi_prior(db, user, profile)
    return {"phi_hours": round(phi, 2), "phi_sd_hours": phi_sd, "chi_w_hours": CHI_W_PRIOR[0],
            "chi_w_sd_hours": CHI_W_PRIOR[1], "personalization_level": "prior_only", "kss_days": 0}
