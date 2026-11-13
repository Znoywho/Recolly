from fastapi import APIRouter
from sqlalchemy.orm import Session

from app.core.deps import CurrentUser, DbSession, response_context
from app.core.errors import ApiError
from app.core.timeutil import clock_from_hours
from app.models.enums import Chronotype, ChronotypeSource, ChronotypeSpectrum, RmeqCategory, SleepConcern
from app.models.health import HealthProfile
from app.models.user import User
from app.schemas.health import (
    ChronotypeAssessment,
    ChronotypeAssessmentRequest,
    HealthProfileInput,
    HealthProfileRead,
    MctqAnswers,
    MctqResult,
    SleepQualityAnswers,
)
from app.service import biorhythm_service
from app.service.sleep import mctq
from app.service.sleep.typical_week import TypicalWeek, WeekSchedule, schedule_from_mctq, simulate_typical_week

router = APIRouter(tags=["Chronotype & profile"])


def _r2(value: float | None) -> float | None:
    return None if value is None else round(value, 2)


def _assess(db: Session, user: User, answers: MctqAnswers | None, rmeq_score: int | None,
            regular_schedule: bool, quality: SleepQualityAnswers | None):
    """Score the questionnaire; also returns the school weekdays and the scored MCTQ answers."""
    days = biorhythm_service.school_days(db, user, answers.work_days if answers else None)
    scored = biorhythm_service.mctq_answers(answers.model_dump() if answers else None, days)
    try:
        result = mctq.assess(scored, rmeq_score, regular_schedule,
                             biorhythm_service.quality_answers(quality.model_dump() if quality else None))
    except ValueError:
        raise ApiError(422, "RMEQ_REQUIRED",
                       "MSFsc cannot be computed (irregular schedule or 7 school days): send rmeq_score") from None
    return result, days, scored


def _mctq_result(result: mctq.ChronotypeAssessment) -> MctqResult | None:
    r = result.mctq
    if r is None:
        return None
    return MctqResult(sd_work_hours=round(r.sd_work, 2), sd_free_hours=round(r.sd_free, 2),
                      sd_week_hours=round(r.sd_week, 2), msw=clock_from_hours(r.msw),
                      msf=clock_from_hours(r.msf), msf_sc=clock_from_hours(r.msf_sc),
                      oversleep_corrected=r.oversleep_corrected,
                      social_jetlag_hours=round(r.social_jetlag, 2), chronotype=result.animal)


def _typical_week(week: TypicalWeek, shift_minutes: int) -> dict:
    return {
        "phi_hours": round(week.phi_hours, 2),
        "school_onset_shift_minutes": shift_minutes,
        "days": [{
            "day": d.day,
            "wake_time": clock_from_hours(d.wake_hour),
            "sleep_time": clock_from_hours(d.sleep_hour),
            "kss_08": _r2(d.kss_at[8]),
            "kss_14": _r2(d.kss_at[14]),
            "kss_22": _r2(d.kss_at[22]),
            "worst_time": clock_from_hours(d.worst_hour),
            "worst_kss": round(d.worst_kss, 2),
            "minutes_past_threshold": d.minutes_past_threshold,
            "peak_start": None if d.peak_start_hour is None else clock_from_hours(d.peak_start_hour),
            "peak_mean_kss": _r2(d.peak_mean_kss),
        } for d in week.days],
        # Every 15 min (the model runs in 5-min steps): 7 x 96 = 672 points.
        "points": [{"day": p.day, "time": clock_from_hours(p.hour), "asleep": p.asleep,
                    "alertness": round(p.alertness, 3), "kss": _r2(p.kss)} for p in week.points[::3]],
    }


@router.post("/chronotype/assess", response_model=ChronotypeAssessment)
def assess_chronotype(body: ChronotypeAssessmentRequest, user: CurrentUser, db: DbSession):
    """C1 · Score the questionnaire and simulate the typical week; nothing is stored."""
    result, days, scored = _assess(db, user, body.mctq, body.rmeq_score, body.regular_schedule,
                                   body.sleep_quality)
    if scored is not None:
        schedule = schedule_from_mctq(scored, days)
    else:
        natural = (result.natural_sleep_time, result.natural_wake_time)
        schedule = WeekSchedule(natural, natural, days)
    schedule = schedule.shift_school_onset(body.school_onset_shift_minutes / 60)
    week = simulate_typical_week(schedule, result.phi_hours)
    return ChronotypeAssessment(
        chronotype=result.animal,
        spectrum=result.spectrum,
        sleep_concern=result.sleep_concern,
        source=result.source,
        mctq_result=_mctq_result(result),
        rmeq_category=result.rmeq_category,
        phi_prior_hours=round(result.phi_hours, 2),
        phi_prior_sd_hours=result.phi_sd_hours,
        natural_sleep_time=clock_from_hours(result.natural_sleep_time),
        natural_wake_time=clock_from_hours(result.natural_wake_time),
        sleep_shortfall_hours=_r2(result.sleep_shortfall_hours),
        typical_week=_typical_week(week, body.school_onset_shift_minutes),
    )


@router.get("/health-profile", response_model=HealthProfileRead)
def get_health_profile(user: CurrentUser):
    """H1 · Sleep profile; 404 HEALTH_PROFILE_NOT_FOUND before onboarding."""
    profile = biorhythm_service.require_profile(user)
    return HealthProfileRead.model_validate(profile, context=response_context(user))


@router.put("/health-profile", response_model=HealthProfileRead)
def put_health_profile(body: HealthProfileInput, user: CurrentUser, db: DbSession):
    """H2 · Create or replace the profile. Chronotype source: mctq > rmeq > self_report."""
    if body.mctq is not None or body.rmeq_score is not None:
        result, _, _ = _assess(db, user, body.mctq, body.rmeq_score, body.regular_schedule,
                               body.sleep_quality)
        mctq_result = _mctq_result(result)
        computed = {
            "chronotype": Chronotype(result.animal),
            "spectrum": ChronotypeSpectrum(result.spectrum),
            "chronotype_source": ChronotypeSource(result.source),
            "sleep_concern": SleepConcern(result.sleep_concern),
            "rmeq_category": RmeqCategory(result.rmeq_category) if result.rmeq_category else None,
            "mctq_result": mctq_result.model_dump(mode="json") if mctq_result else None,
        }
    else:
        quality = biorhythm_service.quality_answers(
            body.sleep_quality.model_dump() if body.sleep_quality else None)
        computed = {
            "chronotype": body.chronotype or Chronotype.BEAR,
            "spectrum": None,
            "chronotype_source": ChronotypeSource.SELF_REPORT,
            "sleep_concern": SleepConcern(mctq.sleep_concern(quality)),
            "rmeq_category": None,
            "mctq_result": None,
        }
    fields = {
        **computed,
        "usual_sleep_time": body.usual_sleep_time,
        "usual_wake_time": body.usual_wake_time,
        "sleep_need_hours": body.sleep_need_hours,
        "morning_prep_minutes": body.morning_prep_minutes,
        "mctq": body.mctq.model_dump(mode="json") if body.mctq else None,
        "rmeq_score": body.rmeq_score,
        "regular_schedule": body.regular_schedule,
        "sleep_quality": body.sleep_quality.model_dump(mode="json") if body.sleep_quality else None,
        "screen_tracking_enabled": body.screen_tracking_enabled,
    }
    profile = user.health_profile
    if profile is None:
        user.health_profile = profile = HealthProfile(user_id=user.id, **fields)
    else:
        for field, value in fields.items():
            setattr(profile, field, value)
    db.flush()
    return HealthProfileRead.model_validate(profile, context=response_context(user))
