from dataclasses import asdict
from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import AfterValidator
from sqlalchemy import select

from app.core.deps import CurrentUser, DbSession, response_context, user_tz
from app.core.timeutil import day_start, today
from app.models.enums import SleepSource
from app.models.health import SleepLog
from app.schemas.health import Biorhythm
from app.service import biorhythm_service
from app.service.sleep.timeline import Point, Window, alertness_score, kss_band

router = APIRouter(tags=["Biorhythm"])

INTERVALS = (5, 15, 30, 60)


def _interval(value: int) -> int:
    # A Literal[5, 15, 30, 60] would reject query strings like "15".
    if value not in INTERVALS:
        raise ValueError("must be 5, 15, 30 or 60")
    return value


def point_out(point: Point) -> dict:
    kss = point.kss
    low, high = kss_band(kss) if kss is not None else (None, None)
    return {
        "time": point.time,
        "asleep": point.asleep,
        "sleep_state": point.sleep_state,
        "process_s": round(min(1.0, max(0.0, point.process_s)), 3),
        "process_c": round(point.process_c, 3),
        "upper_threshold": round(point.upper_threshold, 3),
        "lower_threshold": round(point.lower_threshold, 3),
        "alertness": round(point.alertness, 3),
        "kss_pred": None if kss is None else round(kss, 2),
        "kss_lo": None if low is None else round(low, 2),
        "kss_hi": None if high is None else round(high, 2),
        "alertness_score": None if kss is None else alertness_score(kss),
    }


def window_out(window: Window) -> dict:
    return {"start": window.start, "end": window.end, "mean_kss_pred": round(window.mean_kss, 2),
            "alertness_score": alertness_score(window.mean_kss)}


@router.get("/biorhythm", response_model=Biorhythm)
def get_biorhythm(
    user: CurrentUser,
    db: DbSession,
    date_: Annotated[date | None, Query(alias="date")] = None,
    days: Annotated[int, Query(ge=1, le=7)] = 1,
    interval_minutes: Annotated[int, Query(json_schema_extra={"enum": list(INTERVALS)}),
                                AfterValidator(_interval)] = 15,
):
    """H8 · Process S/C, predicted KSS, golden hours and projected sleep for 1-7 days."""
    profile = biorhythm_service.require_profile(user)
    tz = user_tz(user)
    first = date_ or today(tz)
    timeline = biorhythm_service.timeline_for(db, user, profile, first, days)

    peaks, lows = [], []
    for offset in range(days):
        day_peaks, day_lows = timeline.windows(first + timedelta(days=offset))
        peaks += day_peaks
        lows += day_lows

    warnings = ["PRIOR_ONLY"]
    if not biorhythm_service.has_sleep_logs(db, user):
        warnings.append("TYPICAL_WEEK")
    else:
        recent = biorhythm_service.confirmed_logs(db, user, day_start(first - timedelta(days=7), tz),
                                                  day_start(first, tz))
        if len(recent) < 2:
            warnings.append("NO_RECENT_SLEEP_DATA")
        unconfirmed = db.scalar(select(SleepLog.id).where(
            SleepLog.user_id == user.id, SleepLog.source == SleepSource.SCREEN_INFERRED,
            SleepLog.confirmed.is_(False)).limit(1))
        if unconfirmed is not None:
            warnings.append("UNCONFIRMED_SLEEP_DATA")

    return Biorhythm.model_validate({
        "date": first,
        "days": days,
        "interval_minutes": interval_minutes,
        "timezone": user.timezone,
        "model": biorhythm_service.model_summary(db, user, profile),
        "points": [point_out(p) for p in timeline.points(interval_minutes)],
        "peak_windows": [window_out(w) for w in peaks],
        "low_windows": [window_out(w) for w in lows],
        "projected_sleep": [asdict(timeline.night(first + timedelta(days=offset))) for offset in range(days)],
        "warnings": warnings,
    }, context=response_context(user))
