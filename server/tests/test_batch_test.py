from pathlib import Path

from scripts.batch_test import kind_of, summary_line


def test_kind_of_routes_by_extension():
    assert kind_of(Path("a.M4A")) == "voice"
    assert kind_of(Path("tkb.jpeg")) == "ocr"
    assert kind_of(Path("notes.txt")) is None


def test_summary_line_reports_failures():
    record = {"kind": "ocr", "body": {"status": "failed", "error": "OCR_MODEL_ERROR", "result": None}}
    assert summary_line(record) == "FAILED: OCR_MODEL_ERROR"
