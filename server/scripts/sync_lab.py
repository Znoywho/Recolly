"""Hands-on lab for the Google Calendar sync, the scheduler and reminders (see docs/sync_test_cases.md).

Runs inside the server container against the real API and the real Google account of one user:
    docker exec -i recolly-server-container python - <command> [args] < server/scripts/sync_lab.py

Everything it creates is titled "[TEST] …"; `cleanup` deletes those again (also on Google).
Times are "YYYY-MM-DD HH:MM" in the user's timezone. Ids may be shortened to their first 8 characters.
"""

import argparse
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import httpx
from sqlalchemy import String, cast, select

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.models.event import Event
from app.models.todo import Todo
from app.models.user import User
from app.service import reminders
from app.service.calendar_sync import _access_token
from app.service.google import get_google_client

API = "http://localhost:8765/api/v1"
PREFIX = "[TEST] "


def lab_user(db) -> User:
    """The user who signed in most recently (the lab acts as that user)."""
    user = db.scalar(select(User).order_by(User.last_login_at.desc().nulls_last()))
    if user is None:
        sys.exit("No user yet: sign in once in the app first.")
    return user


def api(user: User) -> httpx.Client:
    """HTTP client authenticated as `user` (same token the app would send)."""
    return httpx.Client(base_url=API, timeout=90,
                        headers={"Authorization": f"Bearer {create_access_token(user.id)}"})


def at(text: str, tz: ZoneInfo) -> datetime:
    """'YYYY-MM-DD HH:MM' in the user's timezone."""
    return datetime.strptime(text, "%Y-%m-%d %H:%M").replace(tzinfo=tz)


def full_id(db, model, prefix: str) -> str:
    """Expand a shortened id; exits when it matches nothing or several rows."""
    ids = db.scalars(select(model.id).where(cast(model.id, String).like(f"{prefix}%"))).all()
    if len(ids) != 1:
        sys.exit(f"Id '{prefix}' matches {len(ids)} rows.")
    return str(ids[0])


def check(response: httpx.Response) -> dict:
    """The JSON answer, or exit with the API error."""
    if response.status_code >= 400:
        sys.exit(f"HTTP {response.status_code}: {response.text}")
    return response.json() if response.content else {}


def clock(value: str) -> str:
    """'2026-12-01T07:30:00+07:00' -> '12-01 07:30'."""
    return value[5:16].replace("T", " ")


def print_saved(answer: dict) -> None:
    """Clashes and blocks moved by an E2/E4/D2/D4 answer."""
    for clash in answer.get("clashes", []):
        print(f"  ⚠ trùng giờ: {clash['title']} {clock(clash['start_at'])}–{clash['end_at'][11:16]}"
              f" ({clash['source']}{', dời được' if clash['movable'] else ''})")
    for moved in answer.get("rescheduled", []):
        print(f"  ↪ khối học dời sang {clock(moved['start_at'])}–{moved['end_at'][11:16]}: {moved['title']}")


# ─────────────────────────── commands ───────────────────────────

def cmd_status(db, user, http, args):
    """Connection, mode, policy, pending and conflict counts."""
    print(check(http.get("/calendar/status")))


def cmd_list(db, user, http, args):
    """App events of the next N days with their sync state."""
    tz = ZoneInfo(user.timezone)
    start = datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)
    items = check(http.get("/events", params={"from": start.isoformat(),
                                               "to": (start + timedelta(days=args.days)).isoformat()}))["items"]
    for e in items:
        google = "G" if e["google_event_id"] else "-"
        print(f"{e['id'][:8]} {clock(e['start_at'])}–{e['end_at'][11:16]} {e['kind']:7} {e['source']:9} "
              f"{e['sync_status']:10} {google} {e['title']}")


def cmd_google(db, user, http, args):
    """Events on the target Google calendar (what Google really has) for the next N days."""
    conn = user.calendar_connection
    if conn is None:
        sys.exit("Not connected to Google Calendar.")
    google = get_google_client()
    now = datetime.now(ZoneInfo(user.timezone))
    for item in google.busy_events(_access_token(conn, google), conn.calendar_id, now - timedelta(hours=12),
                                   now + timedelta(days=args.days)):
        print(f"{item['id'][:12]} {clock(item['start']['dateTime'])}–{item['end']['dateTime'][11:16]} "
              f"{item.get('summary', '')}")


def cmd_event(db, user, http, args):
    """add / move / rename / delete one event."""
    tz = ZoneInfo(user.timezone)
    if args.action == "add":
        start = at(args.when, tz)
        answer = check(http.post("/events", json={
            "title": PREFIX + args.title, "start_at": start.isoformat(),
            "end_at": (start + timedelta(minutes=args.minutes)).isoformat(), "kind": args.kind}))
        print(f"tạo {answer['id'][:8]} {answer['sync_status']}")
        print_saved(answer)
        return
    event_id = full_id(db, Event, args.id)
    if args.action == "delete":
        check(http.delete(f"/events/{event_id}"))
        print("đã xoá")
        return
    if args.action == "move":
        event = check(http.get(f"/events/{event_id}"))
        length = datetime.fromisoformat(event["end_at"]) - datetime.fromisoformat(event["start_at"])
        start = at(args.when, tz)
        body = {"start_at": start.isoformat(), "end_at": (start + length).isoformat()}
    else:
        body = {"title": PREFIX + args.title}
    answer = check(http.patch(f"/events/{event_id}", json=body))
    print(f"sửa {event_id[:8]} {answer['sync_status']}")
    print_saved(answer)


def cmd_todo(db, user, http, args):
    """add / done / delete one todo."""
    tz = ZoneInfo(user.timezone)
    if args.action == "add":
        body = {"title": PREFIX + args.title, "category": args.category}
        if args.deadline:
            body["deadline_at"] = at(args.deadline, tz).isoformat()
        if args.estimate:
            body["estimated_minutes"] = args.estimate
        if args.at:
            start = at(args.at, tz)
            body |= {"start_at": start.isoformat(), "end_at": (start + timedelta(minutes=args.minutes)).isoformat()}
        answer = check(http.post("/todos", json=body))
        print(f"todo {answer['id'][:8]} difficulty={answer['difficulty']}")
        print_saved(answer)
        return
    todo_id = full_id(db, Todo, args.id)
    if args.action == "done":
        check(http.patch(f"/todos/{todo_id}", json={"status": "done"}))
    else:
        check(http.delete(f"/todos/{todo_id}"))
    print("xong")


def cmd_plan(db, user, http, args):
    """CP-SAT: plan every open todo over the next N days, show why each block landed where, then save."""
    today = datetime.now(ZoneInfo(user.timezone)).date()
    plan = check(http.post("/schedule/generate", json={"from": today.isoformat(),
                                                       "to": (today + timedelta(days=args.days - 1)).isoformat()}))
    study = [b for b in plan["blocks"] if b["kind"] == "study"]
    for b in study:
        print(f"{clock(b['start_at'])}–{b['end_at'][11:16]} focus={b['focus']:6} window={b['window']:6} "
              f"KSS={b['predicted_kss']} {b['title']}")
    for u in plan["unscheduled"]:
        print(f"chưa xếp được {u['todo_id'][:8]}: {u['reason']} ({u['missing_minutes']} phút)")
    print(f"giờ vàng: {plan['stats']['golden_hour_ratio']:.0%} thời gian học")
    if study and args.apply:
        check(http.post("/schedule/apply", json={"suggestion_id": plan["suggestion_id"],
                                                 "block_indexes": [b["index"] for b in study]}))
        print(f"đã lưu {len(study)} khối học")


def cmd_sync(db, user, http, args):
    """Manual sync (push + pull when two-way)."""
    print(check(http.post("/calendar/sync", json={})))


def cmd_mode(db, user, http, args):
    """Change the sync mode."""
    print(check(http.patch("/calendar/settings", json={"sync_mode": args.mode}))["sync_mode"])


def cmd_policy(db, user, http, args):
    """Change the conflict policy."""
    print(check(http.patch("/calendar/settings", json={"conflict_policy": args.policy}))["conflict_policy"])


def cmd_conflicts(db, user, http, args):
    """Open conflicts: the app version vs the Google version."""
    for c in check(http.get("/calendar/conflicts"))["items"]:
        print(f"{c['id'][:8]} app: {c['local']['title']} {clock(c['local']['start_at'])} | "
              f"google: {c['google']['title']} {clock(c['google']['start_at'])}")


def cmd_resolve(db, user, http, args):
    """Keep one side of a conflict."""
    from app.models.event import SyncConflict

    check(http.post(f"/calendar/conflicts/{full_id(db, SyncConflict, args.id)}/resolve", json={"keep": args.keep}))
    print("đã giải quyết")


def cmd_reminders(db, user, http, args):
    """Which notifications would fire in [time, time + hours) — nothing is sent."""
    tz = ZoneInfo(user.timezone)
    start = at(args.when, tz)
    due = reminders.due_reminders(db, user, start, start + timedelta(hours=args.hours))
    for payload in due:
        print(f"{payload['type']:8} {payload['title']} — {payload['body']}")
    if not due:
        print("không có thông báo nào trong khoảng này")


def cmd_cleanup(db, user, http, args):
    """Delete every [TEST] event and todo (their Google copies go too)."""
    for event_id in db.scalars(select(Event.id).where(Event.user_id == user.id, Event.title.like(f"{PREFIX}%"))):
        http.delete(f"/events/{event_id}")
    for todo_id in db.scalars(select(Todo.id).where(Todo.user_id == user.id, Todo.title.like(f"{PREFIX}%"))):
        http.delete(f"/todos/{todo_id}")
    print("đã dọn; chạy `sync` nếu đang ở chế độ off")


def parser() -> argparse.ArgumentParser:
    """Command line: one sub-command per lab action."""
    p = argparse.ArgumentParser(prog="sync_lab")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    for name in ("list", "google"):
        sub.add_parser(name).add_argument("days", type=int, nargs="?", default=7)
    e = sub.add_parser("event")
    e.add_argument("action", choices=["add", "move", "rename", "delete"])
    e.add_argument("id_or_title")
    e.add_argument("when_or_title", nargs="?")
    e.add_argument("--minutes", type=int, default=60)
    e.add_argument("--kind", default="other", choices=["other", "study"])
    t = sub.add_parser("todo")
    t.add_argument("action", choices=["add", "done", "delete"])
    t.add_argument("id_or_title")
    t.add_argument("--category", default="other", choices=["study", "assignment", "exam", "personal", "other"])
    t.add_argument("--deadline")
    t.add_argument("--estimate", type=int)
    t.add_argument("--at", help="fixed slot start")
    t.add_argument("--minutes", type=int, default=60)
    plan = sub.add_parser("plan")
    plan.add_argument("days", type=int, nargs="?", default=3)
    plan.add_argument("--apply", action="store_true")
    sub.add_parser("sync")
    sub.add_parser("mode").add_argument("mode", choices=["off", "push", "two_way"])
    sub.add_parser("policy").add_argument("policy", choices=["ask", "google", "local", "latest"])
    sub.add_parser("conflicts")
    r = sub.add_parser("resolve")
    r.add_argument("id")
    r.add_argument("keep", choices=["google", "local"])
    rem = sub.add_parser("reminders")
    rem.add_argument("when")
    rem.add_argument("hours", type=int, nargs="?", default=24)
    sub.add_parser("cleanup")
    return p


def main() -> None:
    """Run one lab command as the lab user."""
    args = parser().parse_args()
    if args.command == "event":  # add <title> <when> | move <id> <when> | rename <id> <title> | delete <id>
        args.id, args.when = args.id_or_title, args.when_or_title
        args.title = args.when_or_title if args.action == "rename" else args.id_or_title
    if args.command == "todo":
        args.id = args.title = args.id_or_title
    with SessionLocal() as db:
        user = lab_user(db)
        with api(user) as http:
            globals()[f"cmd_{args.command}"](db, user, http, args)


if __name__ == "__main__":
    main()
