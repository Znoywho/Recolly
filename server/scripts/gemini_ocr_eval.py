"""Dev-only (R12): score the server's Gemini timetable reader (service/ocr/gemini_reader.py) on labelled images.

It runs the same code as the server with OCR_PROVIDER=gemini and is scored like the Vintern pipeline.
Needs GEMINI_API_KEY (create one at https://aistudio.google.com/apikey) in the environment or in `.env`.
On the unpaid tier Google may use and review what is sent (https://aistudio.google.com/docs/terms),
so only synthetic images are sent unless --allow-real is given.

Prompt injection (text in a photo that gives the model orders) is limited in layers (service/llm/guard.py);
a prompt rule alone is no guarantee: measure it on the `injection` split. Each report line holds token counts.

Usage (from server/, after scripts.generate_timetables):
    venv/bin/python -m scripts.gemini_ocr_eval --limit 1          # check the key and the model first
    venv/bin/python -m scripts.gemini_ocr_eval --limit 4          # one baseline per template
    venv/bin/python -m scripts.gemini_ocr_eval                    # the whole dev split (36 images)
    venv/bin/python -m scripts.gemini_ocr_eval --folder outputs/ocr_dataset/injection     # 8 attack images
"""

import argparse
import json
import logging
import os
import re
import sys
import time
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

from app.service.llm.gemini_client import (DEFAULT_MODEL_NAME, TOKEN_FIELDS, GeminiBadReply, GeminiClient,
                                           GeminiRejected, GeminiUnavailable)
from app.service.ocr.gemini_reader import MIME_TYPES, GeminiReader
from scripts.ocr_eval import load_photos, print_report

SERVER_DIR = Path(__file__).resolve().parent.parent
PROMPT_VERSION = "v3"  # part of the report name, so replies to different prompts are never mixed


def list_photos(folder: Path, limit: int | None) -> list[Path]:
    """Labelled photos, baselines of different base tables first (same order as the Kaggle notebook)."""
    photos = [path for path in folder.iterdir()
              if path.suffix.lower() in MIME_TYPES and path.with_suffix(".json").exists()]
    photos.sort(key=lambda path: (not path.stem.endswith("-baseline"), path.stem.split("-")[::-1]))
    return photos[:limit]


def is_synthetic(photo: Path) -> bool:
    """True when the photo's label says it was generated (no personal data in it)."""
    label = json.loads(photo.with_suffix(".json").read_text(encoding="utf-8"))
    return "source:synthetic" in label.get("tags", [])


def read_to_record(reader: GeminiReader, photo: Path, today: date) -> dict:
    """One report line, in the same format as scripts.batch_test."""
    started = time.monotonic()
    try:
        raw = reader.read_raw(photo.read_bytes(), photo.suffix)
        subjects = [subject.model_dump(mode="json") for subject in reader.parse(raw, today)]
        body = ({"status": "succeeded", "result": {"subjects": subjects}, "error": None} if subjects
                else {"status": "failed", "result": None, "error": "OCR_NO_TABLE_FOUND"})
    except GeminiBadReply as error:
        print(f"  {error}")
        body = {"status": "failed", "result": None, "error": "OCR_LOW_QUALITY"}
    except GeminiUnavailable as error:  # not scored, and retried on the next run
        print(f"  {error}")
        body = {"status": "failed", "result": None, "error": "OCR_MODEL_ERROR"}
    return {"file": photo.name, "kind": "ocr", "http": 202, "seconds": round(time.monotonic() - started, 1),
            "tokens": reader.client.last_tokens, "body": body}


def total_tokens(report: Path) -> dict[str, int]:
    """Each token count summed over every call written in the report."""
    totals = dict.fromkeys(TOKEN_FIELDS, 0)
    for line in report.read_text(encoding="utf-8").splitlines():
        for field, count in json.loads(line).get("tokens", {}).items():
            totals[field] += count
    return totals


def finished_files(report: Path) -> set[str]:
    """Photos the report already answers (outages are tried again)."""
    if not report.exists():
        return set()
    records = [json.loads(line) for line in report.read_text(encoding="utf-8").splitlines() if line.strip()]
    return {record["file"] for record in records if record["body"]["error"] != "OCR_MODEL_ERROR"}


def run(reader: GeminiReader, photos: list[Path], report: Path, today: date) -> None:
    """Read every photo not yet in the report and append its line."""
    done = finished_files(report)
    report.parent.mkdir(parents=True, exist_ok=True)
    (report.parent / ".gitignore").write_text("*\n")  # reports never belong in git
    for index, photo in enumerate(photos, 1):
        if photo.name in done:
            continue
        reader.client.last_tokens = {}
        record = read_to_record(reader, photo, today)
        with open(report, "a", encoding="utf-8") as out:
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
        count = len((record["body"]["result"] or {}).get("subjects", []))
        tokens = record["tokens"]
        print(f"[{index}/{len(photos)}] {photo.name} {record['seconds']}s: {count} subjects, "
              f"tokens in={tokens.get('total_input_tokens', '?')} out={tokens.get('total_output_tokens', '?')} "
              f"total={tokens.get('total_tokens', '?')} {record['body']['error'] or ''}")


def main() -> None:
    """Run Gemini on a folder of labelled photos and print the scores."""
    parser = argparse.ArgumentParser(description="Score Gemini on labelled timetable images.")
    parser.add_argument("--folder", type=Path, default=SERVER_DIR / "outputs" / "ocr_dataset" / "dev")
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--model", default=DEFAULT_MODEL_NAME)
    parser.add_argument("--allow-real", action="store_true", help="also send photos not tagged source:synthetic")
    args = parser.parse_args()
    logging.basicConfig(level=logging.WARNING, format="  %(message)s")  # show retries on the rate limit
    for env_file in (SERVER_DIR / ".env", SERVER_DIR.parent / ".env"):
        load_dotenv(env_file)
    api_key = os.environ.get("GEMINI_API_KEY") or sys.exit("Set GEMINI_API_KEY (see the top of this file).")
    folder = args.folder.expanduser()
    if not folder.is_dir():
        sys.exit(f"No folder {folder}: run `python -m scripts.generate_timetables` first.")
    photos = list_photos(folder, args.limit)
    real = [photo.name for photo in photos if not is_synthetic(photo)]
    if real and not args.allow_real:
        sys.exit(f"Not sent: {len(real)} photos are not synthetic (e.g. {real[0]}). Read the terms, "
                 "cover personal data, then pass --allow-real.")

    slug = re.sub(r"[^\w.-]", "_", f"{folder.name}_{args.model}_{PROMPT_VERSION}")
    report = SERVER_DIR / "outputs" / f"gemini_{slug}.jsonl"
    try:
        client = GeminiClient(api_key, args.model, timeout_seconds=180, attempts=5)
        run(GeminiReader(client), photos, report, date.today())
    except GeminiRejected as error:
        sys.exit(f"Stopped, the request is rejected: {error}")
    scored, skipped = load_photos(report, folder)
    wanted = {photo.name for photo in photos}
    # A rerun may leave two lines for one photo: keep the last one.
    scored = list({photo.file: photo for photo in scored if photo.file in wanted}.values())
    if skipped:
        print(f"{len(skipped)} report lines not scored (outages).")
    if scored:
        print()
        print_report(scored)
    if report.exists():
        print("tokens (all calls in this report):", total_tokens(report))
    print(f"Report: {report}")


if __name__ == "__main__":
    main()
