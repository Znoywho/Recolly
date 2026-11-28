import json

from scripts.ocr_eval import (Photo, bootstrap_f1_difference, bootstrap_f1_interval, cell_recall,
                              false_positive_rate, load_photos, score, score_by_tag)


def row(name, day, room="B201"):
    return {"name": name, "day_of_week": day, "start_time": "07:00", "end_time": "09:30", "room": room}


def test_score_counts_wrong_missed_and_extra_rows():
    truth = [row("Toán rời rạc", 1), row("Vật lý", 2), row("Hoá", 3)]
    predicted = [row("toán  rời rạc", 1), row("Vật lý", 2, room="B202"), row("Bịa", 5)]

    result = score([(truth, predicted)])

    assert result["matched_rows"] == 2
    assert result["precision"] == result["recall"] == result["f1"] == 2 / 3
    assert result["accuracy_room"] == result["accuracy_exact_row"] == 1 / 3


def test_score_of_a_photo_with_no_prediction_is_zero():
    assert score([([row("Toán", 1)], [])])["f1"] == 0.0


def photo(file, truth, predicted, tags=(), group=""):
    return Photo(file, truth, predicted, tags, group)


def test_cell_recall_finds_names_and_rooms_in_markdown():
    truth = [row("Toán rời rạc", 1), row("Vật lý", 2, room="C101")]

    assert cell_recall([(truth, "| toán<br>rời rạc | B201 | Vật lí | C101 |")]) == 3 / 4


def test_score_by_tag_scores_each_tag_on_its_own_photos():
    photos = [photo("a", [row("Toán", 1)], [row("Toán", 1)], ("grid",)),
              photo("b", [row("Toán", 1)], [], ("list",))]

    result = score_by_tag(photos)

    assert (result["grid"]["f1"], result["list"]["f1"]) == (1.0, 0.0)


def test_false_positive_rate_counts_only_non_timetable_photos():
    photos = [photo("poster", [], [row("Bịa", 1)]), photo("note", [], []), photo("tkb", [row("Toán", 1)], [])]

    assert false_positive_rate(photos) == 1 / 2


def test_bootstrap_resamples_whole_groups():
    # One group holds both photos, so every resample is the same data and the interval has no width.
    photos = [photo("a", [row("Toán", 1)], [row("Toán", 1)], group="g"),
              photo("b", [row("Hoá", 1)], [], group="g")]

    assert bootstrap_f1_interval(photos) == (2 / 3, 2 / 3)


def test_bootstrap_difference_is_paired_on_common_photos():
    worse = [photo(name, [row("Toán", 1)], [], group=name) for name in "abc"]
    better = [photo(name, [row("Toán", 1)], [row("Toán", 1)], group=name) for name in "ab"]

    assert bootstrap_f1_difference(worse, better) == (1.0, 1.0, 1.0)


def test_load_photos_skips_outages_and_unlabelled_files(tmp_path):
    for stem in ("ok", "down"):
        (tmp_path / f"{stem}.json").write_text('{"subjects": [], "tags": ["t"], "group": "g"}')
    records = [("ok", "OCR_NO_TABLE_FOUND"), ("down", "OCR_MODEL_ERROR"), ("nolabel", None)]
    report = tmp_path / "report.jsonl"
    report.write_text("\n".join(json.dumps(
        {"file": f"{stem}.png", "kind": "ocr", "seconds": 1.0, "body": {"error": error, "result": None}})
        for stem, error in records))

    photos, skipped = load_photos(report, tmp_path)

    assert [(p.file, p.tags, p.group) for p in photos] == [("ok.png", ("t",), "g")]
    assert len(skipped) == 2
