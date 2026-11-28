"""The shared cleaning of untrusted text that goes into or comes out of a language model."""

from app.service.llm.guard import clean_text


def test_hidden_characters_and_extra_spaces_are_removed():
    assert clean_text("  Toán\u202e\n\x00 rời\u200brạc\ufeff ") == "Toán rời rạc"


def test_text_is_cut_only_when_a_length_is_given():
    assert clean_text("a" * 300) == "a" * 300
    assert clean_text("abc def", 4) == "abc"
