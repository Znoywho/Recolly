"""Checks for the fixed advice of the three animals."""

import pytest

from app.service.sleep import Animal, advice_for
from app.service.sleep.advice import ANIMAL_ADVICE, COMMON_ADVICE, FACER_CHILDS_2019, WATSON_2015


@pytest.mark.parametrize("animal", list(Animal))
def test_every_animal_gets_its_own_advice_first_then_the_shared_advice(animal):
    advice = advice_for(animal)
    own = ANIMAL_ADVICE[animal]
    assert own
    assert advice == [*own, *COMMON_ADVICE]


@pytest.mark.parametrize("animal", list(Animal))
def test_every_line_has_text_and_a_source_link(animal):
    for line in advice_for(animal):
        assert line.text.strip()
        assert line.source.citation.strip()
        assert line.source.url.startswith("https://")


@pytest.mark.parametrize("animal", list(Animal))
def test_everyone_is_told_to_sleep_at_least_7_hours(animal):
    assert any("ít nhất 7 tiếng" in line.text and line.source is WATSON_2015 for line in advice_for(animal))


def test_only_wolves_get_the_night_owl_intervention():
    wolf_sources = [line.source for line in advice_for(Animal.WOLF)]
    assert FACER_CHILDS_2019 in wolf_sources
    for animal in (Animal.LION, Animal.BEAR):
        assert FACER_CHILDS_2019 not in [line.source for line in advice_for(animal)]


def test_no_line_suggests_sleeping_less_than_7_hours():
    all_lines = [line.text for animal in Animal for line in advice_for(animal)]
    for hours in ("4 tiếng", "5 tiếng", "6 tiếng"):
        assert not [text for text in all_lines if hours in text]
