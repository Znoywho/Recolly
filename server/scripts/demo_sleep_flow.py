"""Dev-only: run the demo flow through the real API — quiz → a week of sleep logs → sleep debt →
golden hours → study schedule — and print what the app would show.

Mints an access token straight from the DB (the app login needs a real Google account), then
calls the API over HTTP like the Flutter app does. Safe to re-run: overlapping sleep logs and an
existing demo todo are skipped.

Usage (inside the server container, which has the DB env):
    docker exec -i recolly-server-container python - < scripts/demo_sleep_flow.py
    docker exec -i recolly-server-container python - you@gmail.com < scripts/demo_sleep_flow.py
The optional email seeds an existing user (e.g. yours after signing in on the emulator);
without it a separate demo user is used.
"""

import sys
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import httpx
from sqlalchemy import select

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.models.user import User

API = "http://localhost:8765/api/v1"
DEMO_SUB, DEMO_EMAIL = "demo-sleep-flow", "demo-sleep-flow@recolly.local"
TODO_TITLE = "Ôn thi Giải tích (demo)"

# A typical student week: short school nights, long weekend nights (clock times in the user's timezone).
SCHOOL_NIGHT = (time(0, 30), time(6, 45))
FREE_NIGHT = (time(1, 30), time(9, 30))
PROFILE = {
    "usual_sleep_time": "00:30", "usual_wake_time": "06:45", "sleep_need_hours": 8.0,
    "mctq": {"sleep_onset_work": "00:30", "sleep_end_work": "06:45",
             "sleep_onset_free": "01:30", "sleep_end_free": "09:30"},
}


def demo_user_token(email: str | None) -> tuple[str, ZoneInfo]:
    """Find the user by email (or get/create the demo user) and mint an access token for it."""
    with SessionLocal() as db:
        if email:
            user = db.scalar(select(User).where(User.email == email))
            if user is None:
                sys.exit(f"No user with email {email}: sign in on the app first.")
        else:
            user = db.scalar(select(User).where(User.google_sub == DEMO_SUB))
            if user is None:
                user = User(google_sub=DEMO_SUB, email=DEMO_EMAIL, display_name="Demo")
                db.add(user)
                db.commit()
        return create_access_token(user.id), ZoneInfo(user.timezone)


def last_week_nights(tz: ZoneInfo, now: datetime) -> list[dict]:
    """Sleep logs for the 7 nights ending this morning; a night is 'free' when the next morning is Sat/Sun.
    A night whose wake time is still in the future (run before waking) is skipped."""
    nights = []
    for back in range(7, 0, -1):
        wake_day = now.date() - timedelta(days=back - 1)
        onset, wake = FREE_NIGHT if wake_day.weekday() >= 5 else SCHOOL_NIGHT
        # Onsets after midnight belong to the wake day; before midnight to the evening before.
        sleep_day = wake_day if onset < time(12) else wake_day - timedelta(days=1)
        wake_at = datetime.combine(wake_day, wake, tz)
        if wake_at <= now:
            nights.append({"sleep_at": datetime.combine(sleep_day, onset, tz).isoformat(),
                           "wake_at": wake_at.isoformat()})
    return nights


def ok(response: httpx.Response) -> dict:
    """Return the JSON body, or stop with the API error so a broken step is obvious."""
    if response.status_code >= 400:
        sys.exit(f"{response.request.method} {response.request.url.path} → {response.status_code}: {response.text}")
    return response.json() if response.content else {}


def run_demo_flow(email: str | None) -> None:
    """Seed quiz + sleep logs + one todo, then print debt, golden hours and the suggested schedule."""
    token, tz = demo_user_token(email)
    now = datetime.now(tz)
    today = now.date()
    with httpx.Client(base_url=API, headers={"Authorization": f"Bearer {token}"}, timeout=60) as api:
        existing = api.get("/health-profile")
        # Never overwrite a real user's quiz answers; seed the demo quiz only when there is none.
        profile = ok(api.put("/health-profile", json=PROFILE)) if existing.status_code == 404 else ok(existing)
        msf_sc = (profile["mctq_result"] or {}).get("msf_sc")
        print(f"1. Quiz → chronotype {profile['chronotype']}, MSFsc {msf_sc}"
              f"{' (existing profile kept)' if existing.status_code != 404 else ''}")

        nights, added = last_week_nights(tz, now), 0
        for night in nights:
            response = api.post("/sleep-logs", json=night)
            if response.status_code != 409:  # 409 = already seeded on an earlier run
                ok(response)
                added += 1
        print(f"2. Sleep logs: {added} added ({len(nights)} finished nights)")

        debt = ok(api.get("/sleep-debt", params={"days": 7}))
        print(f"3. Sleep debt 7 days: {debt['total_debt_minutes'] / 60:.1f} h, "
              f"avg sleep {debt['average_sleep_minutes'] / 60:.1f} h, social jetlag {debt['social_jetlag_hours']} h")

        rhythm = ok(api.get("/biorhythm", params={"days": 2}))
        print("4. Golden hours:")
        for window in rhythm["peak_windows"]:
            print(f"   {window['start'][:16]} → {window['end'][11:16]}  alertness {window['alertness_score']}")
        if rhythm["warnings"]:
            print(f"   warnings: {rhythm['warnings']}")

        todos = ok(api.get("/todos", params={"limit": 100}))["items"]
        if not any(t["title"] == TODO_TITLE for t in todos):
            deadline = datetime.combine(today + timedelta(days=3), time(23, 0), tz)
            ok(api.post("/todos", json={"title": TODO_TITLE, "category": "study", "priority": "high",
                                        "deadline_at": deadline.isoformat(), "estimated_minutes": 240}))
        schedule = ok(api.post("/schedule/generate", json={"from": today.isoformat(),
                                                           "to": (today + timedelta(days=3)).isoformat()}))
        print(f"5. Schedule ({schedule['solver_status']}):")
        for block in schedule["blocks"]:
            print(f"   {block['start_at'][:16]} → {block['end_at'][11:16]}  {block['kind']:<7} {block['title']}"
                  f"  KSS {block['predicted_kss']}")
        for missing in schedule["unscheduled"]:
            print(f"   not scheduled: {missing['reason']}")


if __name__ == "__main__":
    run_demo_flow(sys.argv[1] if len(sys.argv) > 1 else None)
