"""Checks for the simplified chronotype + 2PM service."""

from datetime import datetime, timedelta

import pytest

from app.service.sleep import Animal, Night, ScreenEvent, day_energy, estimate, guess_sleep, sleep_debt, sleep_need
from app.service.sleep.two_process import mid_sleep_offset

# Free-day sleep from the quiz.
LION = Night(23.0, 7.0)    # mid 03:00
BEAR = Night(1.0, 9.0)     # mid 05:00
WOLF = Night(3.0, 11.0)    # mid 07:00
SCHOOL_NIGHT = Night(0.0, 6.5)


def kss_at(energy, hour):
    return next(p.kss for p in energy.points if p.hour == pytest.approx(hour))


def test_phase_offset_matches_research_code():
    assert mid_sleep_offset() == pytest.approx(12.42, abs=0.01)


@pytest.mark.parametrize("quiz, animal", [(LION, Animal.LION), (BEAR, Animal.BEAR), (WOLF, Animal.WOLF)])
def test_quiz_gives_three_animals(quiz, animal):
    c = estimate(quiz)
    assert c.animal is animal
    assert c.nights_used == 0


def test_mid_sleep_across_midnight():
    assert Night(22.0, 6.0).mid_sleep == pytest.approx(2.0)
    assert Night(21.0, 23.0).mid_sleep == pytest.approx(22.0)
    assert estimate(Night(21.0, 23.0)).animal is Animal.LION


def test_real_nights_move_the_chronotype():
    later = [WOLF] * 3
    assert estimate(BEAR, later).animal is Animal.BEAR  # quiz still dominates
    many = estimate(BEAR, [WOLF] * 21)
    assert many.animal is Animal.WOLF
    assert many.nights_used == 21
    assert many.phi_hours > estimate(BEAR).phi_hours


def test_lion_alert_in_the_morning_wolf_in_the_evening():
    lion = day_energy(SCHOOL_NIGHT, estimate(LION).phi_hours)
    wolf = day_energy(SCHOOL_NIGHT, estimate(WOLF).phi_hours)
    assert kss_at(lion, 8) < kss_at(wolf, 8)
    assert kss_at(lion, 22) > kss_at(wolf, 22)


def test_wolf_on_early_schedule_fights_sleep_more():
    phi = estimate(WOLF).phi_hours
    assert day_energy(Night(1.5, 6.5), phi).minutes_past_threshold > 0
    assert (day_energy(Night(1.0, 6.5), phi).minutes_past_threshold
            < day_energy(Night(1.5, 6.5), phi).minutes_past_threshold)


def test_peak_avoids_wake_and_bed_buffers():
    e = day_energy(SCHOOL_NIGHT, estimate(BEAR).phi_hours)
    assert len(e.points) == 288
    assert e.peak_start_hour is not None
    assert 7.0 <= e.peak_start_hour <= 24.0 - 1.0 - 1.5
    assert all(p.kss is None for p in e.points if 0.0 <= p.hour < 6.5)


def test_screen_guess_picks_longest_gap_per_night():
    t = datetime(2026, 10, 19, 22, 0)
    events = [
        ScreenEvent(t, False),                                # 22:00 off
        ScreenEvent(t + timedelta(hours=1), True),            # 23:00 on
        ScreenEvent(t + timedelta(hours=1, minutes=20), False),
        ScreenEvent(t + timedelta(hours=8, minutes=50), True),  # 06:50 on
        ScreenEvent(t + timedelta(hours=10), False),
        ScreenEvent(t + timedelta(hours=11), True),           # 1 h gap, too short
    ]
    guesses = guess_sleep(events)
    assert len(guesses) == 1
    g = guesses[0]
    assert g.night == datetime(2026, 10, 19).date()
    assert (g.start.hour, g.start.minute) == (23, 20)
    assert (g.end.hour, g.end.minute) == (6, 50)


def test_screen_guess_after_midnight_counts_for_previous_evening():
    t = datetime(2026, 10, 20, 2, 0)
    guesses = guess_sleep([ScreenEvent(t, False), ScreenEvent(t + timedelta(hours=7), True)])
    assert guesses[0].night == datetime(2026, 10, 19).date()


def test_screen_guess_without_data():
    assert guess_sleep([]) == []


def test_sleep_need_is_personal_but_at_least_7h():
    assert sleep_need() == 8.0
    assert sleep_need(quiz=WOLF) == 8.0
    assert sleep_need(quiz=Night(0.0, 9.0)) == 9.0
    assert sleep_need(user_hours=7.5, quiz=Night(0.0, 9.0)) == 7.5  # typed value wins
    assert sleep_need(user_hours=5.0) == 7.0
    assert sleep_need(user_hours=12.0) == 10.0


def test_sleep_debt_adds_up_and_long_nights_pay_back():
    short = Night(1.0, 6.5)    # 5.5 h
    long = Night(23.0, 9.0)    # 10 h
    d = sleep_debt([short] * 4, need_hours=8.0)
    assert d.debt_hours == pytest.approx(10.0)
    assert d.average_sleep_hours == pytest.approx(5.5)
    assert sleep_debt([short] * 4 + [long], 8.0).debt_hours == pytest.approx(8.0)
    assert sleep_debt([long, short], 8.0).debt_hours == pytest.approx(0.5)  # earlier extra sleep counts too
    assert sleep_debt([long] * 3, 8.0).debt_hours == 0.0


def test_same_nights_different_need():
    nights = [Night(0.0, 7.0)] * 7   # 7 h
    assert sleep_debt(nights, sleep_need(user_hours=7.0)).debt_hours == 0.0
    assert sleep_debt(nights, sleep_need(user_hours=9.0)).debt_hours == pytest.approx(14.0)


def test_sleep_debt_only_counts_last_week_and_handles_no_data():
    old = [Night(3.0, 6.0)] * 10      # 3 h nights, long ago
    recent = [Night(23.0, 7.0)] * 7   # 8 h
    assert sleep_debt(old + recent, 8.0).debt_hours == 0.0
    empty = sleep_debt([], 8.0)
    assert (empty.nights, empty.debt_hours, empty.average_sleep_hours) == (0, 0.0, None)


def test_screen_guess_feeds_sleep_debt():
    t = datetime(2026, 10, 19, 23, 30)
    g = guess_sleep([ScreenEvent(t, False), ScreenEvent(t + timedelta(hours=6), True)])
    assert sleep_debt([g[0].to_night()], 8.0).debt_hours == pytest.approx(2.0)
