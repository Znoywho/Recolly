"""scripts/notebook_report.py: one escaped, summarized section per .jsonl file."""

import json

from scripts.notebook_report import build_report


def test_report_escapes_cells_and_summarizes(tmp_path):
    rows = [{"llm_model": "qwen", "transcript": "<b>hi</b>", "draft": {"title": "x"}, "processing_seconds": 1.0,
             "error": None},
            {"llm_model": "qwen", "transcript": "ok", "processing_seconds": 3.0, "error": "timeout"}]
    (tmp_path / "parser_results.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n")

    page = build_report(tmp_path)

    assert "parser_results.jsonl" in page
    assert "&lt;b&gt;hi&lt;/b&gt;" in page and "<b>hi</b>" not in page
    assert "2 rows" in page and "mean 2.00s / row" in page and "1 errors" in page
    assert "model: qwen" in page


def test_empty_folder_says_so(tmp_path):
    assert "No .jsonl files found." in build_report(tmp_path)
