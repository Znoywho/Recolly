"""Dev-only: send every audio/image file in a folder through the real voice and OCR APIs, one by one.

Audio (.wav .m4a .mp3 .ogg .aac .mp4) → POST /voice/transcribe (200, or 202 then poll /voice/jobs/{id}).
Images (.jpg .jpeg .png .heic)        → POST /ocr/timetable, then poll /ocr/jobs/{id}.
Each result is printed and appended to outputs/batch_<time>.jsonl, so runs can be compared later.

Usage (from server/, the stack running with `docker compose up`):
    export RECOLLY_TOKEN=$(docker exec recolly-server-container python -c "
    from sqlalchemy import select; from app.db.session import SessionLocal; from app.models.user import User
    from app.core.security import create_access_token
    print(create_access_token(SessionLocal().scalar(select(User).limit(1)).id))")
    venv/bin/python -m scripts.batch_test ~/recolly-test-files
"""

import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import httpx

API = os.environ.get("RECOLLY_API", "http://localhost:8765/api/v1")
AUDIO_SUFFIXES = {".wav", ".m4a", ".mp3", ".ogg", ".aac", ".mp4"}
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".heic"}
POLL_SECONDS, POLL_LIMIT_SECONDS = 2, 600


def kind_of(path: Path) -> str | None:
    """'voice' / 'ocr' from the file extension, None for files to skip."""
    suffix = path.suffix.lower()
    return "voice" if suffix in AUDIO_SUFFIXES else "ocr" if suffix in IMAGE_SUFFIXES else None


def post_with_retry(client: httpx.Client, url: str, field: str, path: Path) -> httpx.Response:
    """POST the file; on 429 wait for Retry-After (OCR allows 10 uploads per minute) and try again."""
    while True:
        with open(path, "rb") as file:
            response = client.post(url, files={field: (path.name, file)})
        if response.status_code != 429:
            return response
        wait = int(response.headers.get("Retry-After", "60"))
        print(f"  rate limited, waiting {wait}s")
        time.sleep(wait)


def poll_job(client: httpx.Client, url: str) -> dict:
    """GET the job until it is no longer queued/processing (or give up after POLL_LIMIT_SECONDS)."""
    deadline = time.monotonic() + POLL_LIMIT_SECONDS
    while True:
        job = client.get(url).raise_for_status().json()
        if job["status"] not in ("queued", "processing") or time.monotonic() > deadline:
            return job
        time.sleep(POLL_SECONDS)


def run_one(client: httpx.Client, path: Path, kind: str) -> dict:
    """Send one file through its API and return a flat record of what came back."""
    started = time.monotonic()
    if kind == "voice":
        response = post_with_retry(client, f"{API}/voice/transcribe", "audio", path)
        body = response.json()
        if response.status_code == 202:
            job = poll_job(client, f"{API}/voice/jobs/{body['job_id']}")
            body = job["result"] or job
    else:
        response = post_with_retry(client, f"{API}/ocr/timetable", "image", path)
        body = response.json()
        if response.status_code == 202:
            body = poll_job(client, f"{API}/ocr/jobs/{body['job_id']}")
    return {"file": path.name, "kind": kind, "http": response.status_code,
            "seconds": round(time.monotonic() - started, 1), "body": body}


def summary_line(record: dict) -> str:
    """One readable line per file: transcript + draft for voice, subject count for OCR."""
    body = record["body"]
    if record["kind"] == "voice" and "transcript" in body:
        draft = body.get("todo_draft") or {}
        return f"'{body['transcript']}' → {draft.get('title')} | {draft.get('deadline_at')} ({body['parser']})"
    if record["kind"] == "ocr" and body.get("result"):
        return f"{len(body['result']['subjects'])} subjects"
    return f"FAILED: {body.get('error') or body}"


def main() -> None:
    """Run every supported file in the folder given on the command line."""
    token = os.environ.get("RECOLLY_TOKEN") or sys.exit("Set RECOLLY_TOKEN first (see the docstring).")
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else ".").expanduser()
    files = sorted(p for p in folder.rglob("*") if p.is_file() and kind_of(p))
    if not files:
        sys.exit(f"No audio or image files in {folder}")

    report = Path("outputs") / f"batch_{datetime.now():%Y%m%d_%H%M%S}.jsonl"
    report.parent.mkdir(exist_ok=True)
    headers = {"Authorization": f"Bearer {token}"}
    with httpx.Client(headers=headers, timeout=300) as client, open(report, "a", encoding="utf-8") as out:
        for index, path in enumerate(files, 1):
            try:
                record = run_one(client, path, kind_of(path))
            except (httpx.HTTPError, ValueError) as error:  # one broken file must not stop the batch
                record = {"file": path.name, "kind": kind_of(path), "http": None, "seconds": None,
                          "body": {"error": repr(error)}}
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
            out.flush()
            print(f"[{index}/{len(files)}] {path.name} ({record['http']}, {record['seconds']}s): "
                  f"{summary_line(record)}")
    print(f"Report: {report}")


if __name__ == "__main__":
    main()
