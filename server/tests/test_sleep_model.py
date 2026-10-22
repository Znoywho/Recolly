"""Acceptance checks for Module 2 (docs/research/TRIEN_KHAI.md §3.5)."""

import pytest

from app.service.sleep import Animal, MctqAnswers, SleepConcern, assess, schedule_from_mctq, simulate_typical_week
from app.service.sleep.chronotype import (
    NightsPerWeek,
    ProblemDuration,
    SleepQualityAnswers,
    Spectrum,
    score_mctq,
    sleep_concern,
)
from app.service.sleep.two_process import mid_sleep_offset, phi_from_mid_sleep

LION = MctqAnswers(22.5, 6.0, 23.0, 7.0, work_days=5)
BEAR = MctqAnswers(0.0, 6.5, 1.0, 9.0, work_days=5)
WOLF = MctqAnswers(1.5, 6.5, 3.5, 11.5, work_days=5)
MONDAY, THURSDAY = 0, 3


def week(answers, phi=None):
    if phi is None:
        phi = assess(answers).phi_hours
    return simulate_typical_week(schedule_from_mctq(answers), phi)


def test_phase_offset_matches_research_code():
    assert mid_sleep_offset() == pytest.approx(12.42, abs=0.01)


def test_mctq_scoring_matches_api_contract_example():
    r = score_mctq(MctqAnswers(0.5, 6.5, 1.75, 10.0, work_days=5))
    assert r.sd_week == pytest.approx(6.64, abs=0.01)
    assert r.msf == pytest.approx(5.875)
    assert r.msf_sc == pytest.approx(5.07, abs=0.01)
    assert r.social_jetlag == pytest.approx(2.38, abs=0.01)
    assert r.oversleep_corrected
    assert assess(MctqAnswers(0.5, 6.5, 1.75, 10.0)).phi_hours == pytest.approx(18.39, abs=0.01)


@pytest.mark.parametrize("answers, animal", [(LION, Animal.LION), (BEAR, Animal.BEAR), (WOLF, Animal.WOLF)])
def test_sample_answers_give_three_animals(answers, animal):
    assert assess(answers).animal is animal


def test_bedtime_before_midnight_counts_as_early():
    r = assess(MctqAnswers(21.0, 5.0, 21.5, 5.5))
    assert r.animal is Animal.LION
    assert r.spectrum is Spectrum.EARLY


def test_no_school_days_uses_free_days_only():
    r = assess(MctqAnswers(0.0, 0.0, 1.0, 9.0, work_days=0))
    assert r.mctq.msf_sc == pytest.approx(r.mctq.msf)
    assert r.mctq.social_jetlag == 0
    assert len(week(MctqAnswers(0.0, 0.0, 1.0, 9.0, work_days=0)).days) == 7


def test_seven_school_days_needs_rmeq():
    answers = MctqAnswers(0.0, 6.5, 0.0, 6.5, work_days=7)
    with pytest.raises(ValueError):
        assess(answers)
    r = assess(answers, rmeq_score=9)
    assert (r.source, r.animal) == ("rmeq", Animal.WOLF)
    assert len(week(answers, r.phi_hours).days) == 7


def test_irregular_schedule_uses_rmeq():
    r = assess(BEAR, rmeq_score=20, regular_schedule=False)
    assert (r.source, r.animal, r.phi_sd_hours) == ("rmeq", Animal.LION, 1.5)


def test_uncertain_prior_when_alarm_or_disagreement():
    assert assess(MctqAnswers(1.5, 6.5, 3.5, 11.5, alarm_on_free_days=True)).phi_sd_hours == 1.5
    assert assess(WOLF, rmeq_score=23).phi_sd_hours == 1.5
    assert assess(WOLF, rmeq_score=14).phi_sd_hours == 1.0


@pytest.mark.parametrize("f1, f2, f3, concern", [
    (NightsPerWeek.NONE, NightsPerWeek.SOME, None, SleepConcern.NONE),
    (NightsPerWeek.MOST, NightsPerWeek.NONE, ProblemDuration.ONE_TO_3_MONTHS, SleepConcern.WATCH),
    (NightsPerWeek.SOME, NightsPerWeek.MOST, ProblemDuration.OVER_3_MONTHS, SleepConcern.DOLPHIN),
])
def test_dolphin_flag(f1, f2, f3, concern):
    assert sleep_concern(SleepQualityAnswers(f1, f2, f3)) is concern


def test_dolphin_does_not_change_the_animal():
    q = SleepQualityAnswers(NightsPerWeek.MOST, NightsPerWeek.MOST, ProblemDuration.OVER_3_MONTHS)
    r = assess(WOLF, sleep_quality=q)
    assert r.dolphin and r.animal is Animal.WOLF


def test_typical_week_matches_research_prototype_without_bias():
    """Same numbers as the sleepResearch prototype when phi has no MCTQ bias correction."""
    wolf = week(WOLF, phi_from_mid_sleep(score_mctq(WOLF).msf_sc))
    monday = wolf.days[MONDAY]
    assert monday.kss_at[8] == pytest.approx(4.7, abs=0.05)
    assert monday.kss_at[22] == pytest.approx(6.6, abs=0.05)
    assert monday.minutes_past_threshold == 75
    assert wolf.days[THURSDAY].minutes_past_threshold == 95


def test_lion_is_more_alert_in_the_morning_wolf_in_the_evening():
    lion, wolf = week(LION).days[MONDAY], week(WOLF).days[MONDAY]
    assert lion.kss_at[8] < wolf.kss_at[8]
    assert lion.kss_at[22] > wolf.kss_at[22]


def test_sleep_pressure_builds_over_the_school_week():
    wolf = week(WOLF)
    assert wolf.days[THURSDAY].kss_at[14] > wolf.days[MONDAY].kss_at[14]
    assert wolf.days[THURSDAY].minutes_past_threshold > wolf.days[MONDAY].minutes_past_threshold


def test_what_if_earlier_bedtime_keeps_phi_and_reduces_time_past_threshold():
    phi = assess(WOLF).phi_hours
    now = simulate_typical_week(schedule_from_mctq(WOLF), phi)
    earlier = simulate_typical_week(schedule_from_mctq(WOLF).shift_school_onset(-0.5), phi)
    assert earlier.phi_hours == now.phi_hours
    assert earlier.days[THURSDAY].minutes_past_threshold < now.days[THURSDAY].minutes_past_threshold


def test_peak_block_skips_the_first_30_minutes_after_waking():
    for day in week(BEAR).days:
        assert (day.peak_start_hour - day.wake_hour) % 24 >= 0.5


def test_week_has_seven_days_of_points():
    w = week(BEAR)
    assert len(w.points) == 7 * 288
    assert [d.day for d in w.days] == list(range(7))
    assert all(p.kss is None for p in w.points if p.asleep)
