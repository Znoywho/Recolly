"""The synthetic timetable generator: labels must be valid and repeatable."""

import json
import zipfile
from datetime import date
from pathlib import Path

import pytest

pytest.importorskip("PIL")

from app.schemas.timetable import SubjectFields  # noqa: E402
from scripts.generate_timetables import (DEFAULT_FONT, SUBJECT_NAMES, VARIANTS, TimetableRenderer,  # noqa: E402
                                         generate_injection_split, generate_split, make_zip)

needs_font = pytest.mark.skipif(not Path(DEFAULT_FONT).exists(), reason="Noto Sans is not installed")


def read_labels(folder: Path) -> dict:
    return {path.stem: json.loads(path.read_text(encoding="utf-8")) for path in sorted(folder.glob("*.json"))}


def test_no_subject_name_contains_another():
    assert not [(a, b) for a in SUBJECT_NAMES for b in SUBJECT_NAMES if a != b and a.lower() in b.lower()]


@needs_font
def test_split_is_complete_valid_and_repeatable(tmp_path):
    renderer = TimetableRenderer()

    assert generate_split(tmp_path / "one", "dev", 4, 1, renderer) == 4 * len(VARIANTS)
    generate_split(tmp_path / "two", "dev", 4, 1, renderer)

    labels = read_labels(tmp_path / "one")
    assert labels == read_labels(tmp_path / "two")
    assert len(list((tmp_path / "one").glob("*.png"))) == len(list((tmp_path / "one").glob("*.md"))) == len(labels)
    for label in labels.values():
        rows = label["subjects"]
        for row in rows:
            SubjectFields(**row, start_date=date(2026, 9, 7), end_date=date(2026, 12, 20))
        assert len({(row["day_of_week"], row["start_time"]) for row in rows}) == len(rows)  # no overlap
    dense = labels["dev-grid-period-00-sessions-20"]["subjects"]
    assert dense[:6] == labels["dev-grid-period-00-baseline"]["subjects"] and len(dense) == 20


@needs_font
def test_injection_labels_never_contain_the_attack(tmp_path):
    assert generate_injection_split(tmp_path, TimetableRenderer()) == 8

    for label in read_labels(tmp_path).values():
        assert len(label["subjects"]) == 6 and any(tag.startswith("attack:") for tag in label["tags"])
        assert "ZZQINJECT" not in json.dumps(label["subjects"])


@needs_font
def test_zip_holds_both_splits_and_only_python_code(tmp_path):
    renderer = TimetableRenderer()
    for split in ("dev", "test"):
        generate_split(tmp_path / split, split, 1, 1, renderer)

    generate_injection_split(tmp_path / "injection", renderer)

    make_zip(tmp_path, tmp_path / "data.zip")

    names = zipfile.ZipFile(tmp_path / "data.zip").namelist()
    assert "code/scripts/ocr_eval.py" in names and "code/app/service/ocr/timetable_parser.py" in names
    assert all(name.endswith(".py") for name in names if name.startswith("code/"))
    assert all(any(name.startswith(f"{split}/") for name in names) for split in ("dev", "test", "injection"))
    assert "code/app/service/llm/guard.py" in names
