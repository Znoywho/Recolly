"""Chronotype from the onboarding questionnaire (docs/research/CAU_HOI.md §2).

- Sleep times on school and free days (µMCTQ) -> MSFsc and social jetlag.
- rMEQ total score as a fallback when MSFsc cannot be computed.
- MSFsc -> animal (lion / bear / wolf). The animals are a display layer only;
  everything downstream uses MSFsc and phi as numbers.
- Dolphin is not on the morning-evening axis: it is a separate fragmented-sleep flag.

Sources for every rule: docs/research/TRIEN_KHAI.md §2.1.
"""

from dataclasses import dataclass
from enum import StrEnum

from app.service.sleep.two_process import circular_diff_hours, phi_from_mid_sleep

# Animal cut-offs on MSFsc, placed around the assumed student mean (MSFsc ~05:00).
# Provisional: re-fit on real students, e.g. to 20/60/20 percentiles.
LION_BEFORE_MSF_SC = 4.0
WOLF_FROM_MSF_SC = 6.0

# In synthetic experiment 1 (NGHIEN_CUU.md §3) MCTQ put the phase ~55 min too early,
# so phi from MCTQ is shifted later by this much. Re-calibrate on real data.
MCTQ_PHI_BIAS_HOURS = 0.9
PHI_SD_HOURS = 1.0
PHI_SD_UNCERTAIN_HOURS = 1.5    # alarm on free days, or rMEQ only
PHI_SD_DISAGREEMENT_HOURS = 0.5  # added when MCTQ says lion and rMEQ says wolf (or vice versa)

MIN_SLEEP_HOURS = 7.0           # recommended minimum for adults (Watson et al. 2015)
RMEQ_ONLY_SLEEP_HOURS = 8.0     # natural-window length when there is no MCTQ


class Animal(StrEnum):
    LION = "lion"
    BEAR = "bear"
    WOLF = "wolf"


class Spectrum(StrEnum):
    EARLY = "early"
    SLIGHTLY_EARLY = "slightly_early"
    INTERMEDIATE = "intermediate"
    SLIGHTLY_LATE = "slightly_late"
    LATE = "late"


class SleepConcern(StrEnum):
    NONE = "none"
    WATCH = "watch"      # frequent bad nights for < 3 months: ask again in 4 weeks, no label
    DOLPHIN = "dolphin"  # >= 3 bad nights a week for > 3 months (screening flag, not a diagnosis)


class NightsPerWeek(StrEnum):
    NONE = "0"
    SOME = "1-2"
    MOST = "3+"


class ProblemDuration(StrEnum):
    UNDER_1_MONTH = "<1m"
    ONE_TO_3_MONTHS = "1-3m"
    OVER_3_MONTHS = ">3m"


@dataclass(frozen=True)
class MctqAnswers:
    """Clock hours as floats, e.g. 23.5 = 23:30, 0.75 = 00:45."""

    sleep_onset_work: float
    sleep_end_work: float
    sleep_onset_free: float
    sleep_end_free: float
    work_days: int = 5
    alarm_on_free_days: bool = False


@dataclass(frozen=True)
class MctqResult:
    sd_work: float
    sd_free: float
    sd_week: float
    msw: float
    msf: float
    msf_sc: float
    oversleep_corrected: bool
    social_jetlag: float


@dataclass(frozen=True)
class SleepQualityAnswers:
    slow_onset_nights: NightsPerWeek          # F1: > 30 min to fall asleep
    night_waking_nights: NightsPerWeek        # F2: awake at night / too early and cannot fall back asleep
    duration: ProblemDuration | None = None   # F3: only asked when F1 or F2 is "3+"


@dataclass(frozen=True)
class ChronotypeAssessment:
    animal: Animal
    spectrum: Spectrum
    sleep_concern: SleepConcern
    source: str                     # "mctq" or "rmeq"
    mctq: MctqResult | None
    rmeq_score: int | None
    rmeq_category: str | None
    phi_hours: float
    phi_sd_hours: float
    natural_sleep_time: float
    natural_wake_time: float
    sleep_shortfall_hours: float | None  # below the 7 h minimum, from the weekly average

    @property
    def dolphin(self) -> bool:
        return self.sleep_concern is SleepConcern.DOLPHIN


def _duration(onset: float, end: float) -> float:
    return (end - onset) % 24


def score_mctq(a: MctqAnswers) -> MctqResult:
    """MSF, MSFsc and social jetlag (Roenneberg et al. 2003; Wittmann et al. 2006).

    With work_days = 0 the work-day times are ignored and every day counts as free (MSFsc = MSF).
    work_days = 7 has no free day, so MSF does not exist: use the rMEQ instead.
    """
    if not 0 <= a.work_days <= 6:
        raise ValueError("MSF needs at least one free day (work_days 0..6)")
    onset_w, end_w = ((a.sleep_onset_free, a.sleep_end_free) if a.work_days == 0
                      else (a.sleep_onset_work, a.sleep_end_work))
    sd_w = _duration(onset_w, end_w)
    sd_f = _duration(a.sleep_onset_free, a.sleep_end_free)
    msw = (onset_w + sd_w / 2) % 24
    msf = (a.sleep_onset_free + sd_f / 2) % 24
    sd_week = (sd_w * a.work_days + sd_f * (7 - a.work_days)) / 7
    corrected = sd_f > sd_w
    msf_sc = (msf - (sd_f - sd_week) / 2) % 24 if corrected else msf
    sjl = abs(circular_diff_hours(msf, msw))
    return MctqResult(sd_w, sd_f, sd_week, msw, msf, msf_sc, corrected, sjl)


def _hours_after_midnight(clock_hour: float) -> float:
    """23:30 -> -0.5, so very early mid-sleeps sort before 00:00."""
    return clock_hour - 24 if clock_hour > 12 else clock_hour


def animal_from_msf_sc(msf_sc: float) -> Animal:
    h = _hours_after_midnight(msf_sc)
    if h < LION_BEFORE_MSF_SC:
        return Animal.LION
    if h >= WOLF_FROM_MSF_SC:
        return Animal.WOLF
    return Animal.BEAR


def spectrum_from_msf_sc(msf_sc: float) -> Spectrum:
    h = _hours_after_midnight(msf_sc)
    if h < 3:
        return Spectrum.EARLY
    if h < 4.5:
        return Spectrum.SLIGHTLY_EARLY
    if h < 5.5:
        return Spectrum.INTERMEDIATE
    if h < 6.5:
        return Spectrum.SLIGHTLY_LATE
    return Spectrum.LATE


def rmeq_category(score: int) -> str:
    """rMEQ, 5 items, total 4..25 (Adan & Almirall 1991)."""
    if not 4 <= score <= 25:
        raise ValueError("rMEQ total score must be within 4..25")
    if score >= 22:
        return "definitely_morning"
    if score >= 18:
        return "moderately_morning"
    if score >= 12:
        return "neither"
    if score >= 8:
        return "moderately_evening"
    return "definitely_evening"


_RMEQ_SPECTRUM = {
    "definitely_morning": Spectrum.EARLY,
    "moderately_morning": Spectrum.SLIGHTLY_EARLY,
    "neither": Spectrum.INTERMEDIATE,
    "moderately_evening": Spectrum.SLIGHTLY_LATE,
    "definitely_evening": Spectrum.LATE,
}
# Representative MSFsc of each animal, used to place phi when only the rMEQ is known.
_ANIMAL_MID_SLEEP = {Animal.LION: 3.0, Animal.BEAR: 5.0, Animal.WOLF: 7.0}
_ANIMAL_RANK = {Animal.LION: 0, Animal.BEAR: 1, Animal.WOLF: 2}


def animal_from_rmeq(score: int) -> Animal:
    rmeq_category(score)  # range check
    if score >= 18:
        return Animal.LION
    if score >= 12:
        return Animal.BEAR
    return Animal.WOLF


def sleep_concern(q: SleepQualityAnswers | None) -> SleepConcern:
    """Dolphin flag. The 3 nights / 3 months marks follow the DSM-5 insomnia frequency and duration."""
    if q is None:
        return SleepConcern.NONE
    if NightsPerWeek.MOST not in (q.slow_onset_nights, q.night_waking_nights):
        return SleepConcern.NONE
    if q.duration is ProblemDuration.OVER_3_MONTHS:
        return SleepConcern.DOLPHIN
    return SleepConcern.WATCH


def assess(mctq: MctqAnswers | None = None, rmeq_score: int | None = None,
           regular_schedule: bool = True,
           sleep_quality: SleepQualityAnswers | None = None) -> ChronotypeAssessment:
    """Score the onboarding questionnaire (TRIEN_KHAI.md §3.2, step 1).

    MCTQ is used when the schedule is regular and there is at least one free day;
    otherwise the rMEQ score is required.
    """
    concern = sleep_concern(sleep_quality)
    rmeq_cat = rmeq_category(rmeq_score) if rmeq_score is not None else None
    use_mctq = mctq is not None and regular_schedule and mctq.work_days < 7

    if use_mctq:
        r = score_mctq(mctq)
        animal = animal_from_msf_sc(r.msf_sc)
        phi_sd = PHI_SD_UNCERTAIN_HOURS if mctq.alarm_on_free_days else PHI_SD_HOURS
        if rmeq_score is not None and abs(
                _ANIMAL_RANK[animal] - _ANIMAL_RANK[animal_from_rmeq(rmeq_score)]) == 2:
            phi_sd += PHI_SD_DISAGREEMENT_HOURS
        return ChronotypeAssessment(
            animal=animal,
            spectrum=spectrum_from_msf_sc(r.msf_sc),
            sleep_concern=concern,
            source="mctq",
            mctq=r,
            rmeq_score=rmeq_score,
            rmeq_category=rmeq_cat,
            phi_hours=(phi_from_mid_sleep(r.msf_sc) + MCTQ_PHI_BIAS_HOURS) % 24,
            phi_sd_hours=phi_sd,
            natural_sleep_time=(r.msf_sc - r.sd_week / 2) % 24,
            natural_wake_time=(r.msf_sc + r.sd_week / 2) % 24,
            sleep_shortfall_hours=max(0.0, MIN_SLEEP_HOURS - r.sd_week),
        )

    if rmeq_score is None:
        raise ValueError("rMEQ score is required when MSFsc cannot be computed")
    animal = animal_from_rmeq(rmeq_score)
    mid = _ANIMAL_MID_SLEEP[animal]
    return ChronotypeAssessment(
        animal=animal,
        spectrum=_RMEQ_SPECTRUM[rmeq_cat],
        sleep_concern=concern,
        source="rmeq",
        mctq=None,
        rmeq_score=rmeq_score,
        rmeq_category=rmeq_cat,
        phi_hours=phi_from_mid_sleep(mid),
        phi_sd_hours=PHI_SD_UNCERTAIN_HOURS,
        natural_sleep_time=(mid - RMEQ_ONLY_SLEEP_HOURS / 2) % 24,
        natural_wake_time=(mid + RMEQ_ONLY_SLEEP_HOURS / 2) % 24,
        sleep_shortfall_hours=None,
    )
