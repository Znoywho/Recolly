import uuid
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import update

from app.config import Config
from app.core.security import channel_token
from app.models.calendar import CalendarConnection
from app.service import calendar_sync
from tests.test_event_api import create as create_event
from tests.test_timetable_api import SUBJECT

API = "/api/v1"
TZ = ZoneInfo("Asia/Ho_Chi_Minh")
NOVEMBER = {"from": "2026-11-01T00:00:00+07:00", "to": "2026-11-30T00:00:00+07:00"}


@pytest.fixture(autouse=True)
def no_pull_cooldown(monkeypatch):
    """Tests sync back-to-back and expect every sync to pull; cooldown tests turn it back on."""
    monkeypatch.setattr(calendar_sync, "PULL_COOLDOWN", timedelta(0))


def sync(client, headers):
    response = client.post(f"{API}/calendar/sync", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def get_event(client, headers, event):
    return client.get(f"{API}/events/{event['id']}", headers=headers).json()


def two_way(client, headers):
    response = client.patch(f"{API}/calendar/settings", json={"two_way_sync": True}, headers=headers)
    assert response.status_code == 200, response.text
    assert response.json()["two_way_sync"] is True


def test_status_when_not_connected(client, auth):
    assert client.get(f"{API}/calendar/status", headers=auth).json() == {
        "connected": False, "google_email": None, "calendar_id": None, "sync_mode": "off",
        "conflict_policy": "ask", "two_way_sync": False,
        "last_synced_at": None, "pending_count": 0, "conflict_count": 0}
    response = client.post(f"{API}/calendar/sync", headers=auth)
    assert response.status_code == 409
    assert response.json()["code"] == "CALENDAR_NOT_CONNECTED"


def test_connecting_queues_existing_events(client, auth, google):
    event = create_event(client, auth)
    google.add_grant("code", sub="sub", email="sv@gmail.com", calendar=True)
    status = client.post(f"{API}/calendar/connection", json={"server_auth_code": "code"}, headers=auth).json()
    assert status["connected"] is True
    assert status["pending_count"] == 1
    assert get_event(client, auth, event)["sync_status"] == "pending"


def test_connect_errors(client, auth, google):
    google.add_grant("no-scope", sub="sub", email="sv@gmail.com", calendar=False)
    google.add_grant("no-refresh", sub="sub", email="sv@gmail.com", calendar=True, refresh_token=None)
    cases = {"no-scope": (403, "GOOGLE_SCOPE_MISSING"), "no-refresh": (400, "GOOGLE_CODE_INVALID"),
             "unknown": (400, "GOOGLE_CODE_INVALID")}
    for code, (status, error) in cases.items():
        response = client.post(f"{API}/calendar/connection", json={"server_auth_code": code}, headers=auth)
        assert (response.status_code, response.json()["code"]) == (status, error)


def test_push_insert_update_delete(client, connected, google):
    event = create_event(client, connected)
    assert sync(client, connected) == {"pushed": 1, "pulled": 0, "failed": 0, "conflicts": 0}
    [item] = google.events()
    assert item["id"] == uuid.UUID(event["id"]).hex
    assert item["summary"] == "Họp nhóm"
    assert item["start"] == {"dateTime": "2026-11-02T19:00:00+07:00", "timeZone": "Asia/Ho_Chi_Minh"}
    synced = get_event(client, connected, event)
    assert synced["sync_status"] == "synced"
    assert synced["google_event_id"] == item["id"]
    assert sync(client, connected)["pushed"] == 0

    client.patch(f"{API}/events/{event['id']}", json={"title": "Họp lớp"}, headers=connected)
    assert sync(client, connected)["pushed"] == 1
    assert google.events()[0]["summary"] == "Họp lớp"

    client.delete(f"{API}/events/{event['id']}", headers=connected)
    assert client.get(f"{API}/calendar/status", headers=connected).json()["pending_count"] == 1
    assert sync(client, connected)["pushed"] == 1
    assert google.events() == []


def test_class_events_are_pushed_as_one_recurring_event(client, connected, google):
    client.post(f"{API}/timetable", json={"subjects": [SUBJECT]}, headers=connected)
    sync(client, connected)
    [item] = google.events()
    assert item["recurrence"] == ["RRULE:FREQ=WEEKLY;BYDAY=WE;UNTIL=20261220T165959Z"]
    assert item["colorId"] == "9"
    assert item["start"]["dateTime"] == "2026-09-09T07:30:00+07:00"


def test_retry_after_a_lost_answer_does_not_duplicate(client, connected, google):
    event = create_event(client, connected)
    # An earlier push reached Google but its answer was lost.
    google.insert_event("access-token", "primary", {"id": uuid.UUID(event["id"]).hex, "summary": "old"})
    assert sync(client, connected)["pushed"] == 1
    assert [e["summary"] for e in google.events()] == ["Họp nhóm"]


def test_two_way_pulls_edits_new_events_and_deletes(client, connected, google):
    two_way(client, connected)
    event = create_event(client, connected)
    assert sync(client, connected) == {"pushed": 1, "pulled": 0, "failed": 0, "conflicts": 0}

    google.edit_on_google(uuid.UUID(event["id"]).hex, summary="Đổi tên trên Google")
    added = google.add_on_google("Sinh nhật", datetime(2026, 11, 3, 18, 0, tzinfo=TZ))
    assert sync(client, connected) == {"pushed": 0, "pulled": 2, "failed": 0, "conflicts": 0}
    assert get_event(client, connected, event)["title"] == "Đổi tên trên Google"
    events = client.get(f"{API}/events", params={**NOVEMBER, "source": "google"}, headers=connected).json()
    [birthday] = events["items"]
    assert birthday["title"] == "Sinh nhật"
    assert birthday["sync_status"] == "synced"
    assert birthday["start_at"] == "2026-11-03T18:00:00+07:00"

    google.delete_on_google(added["id"])
    assert sync(client, connected)["pulled"] == 1
    assert client.get(f"{API}/events/{birthday['id']}", headers=connected).status_code == 404


def test_sync_inside_cooldown_skips_pull_but_still_pushes(client, connected, google, monkeypatch, db):
    monkeypatch.setattr(calendar_sync, "PULL_COOLDOWN", timedelta(minutes=2))
    two_way(client, connected)
    sync(client, connected)
    last_synced = client.get(f"{API}/calendar/status", headers=connected).json()["last_synced_at"]

    google.add_on_google("Từ Google", datetime(2026, 11, 3, 18, 0, tzinfo=TZ))
    create_event(client, connected)
    assert sync(client, connected) == {"pushed": 1, "pulled": 0, "failed": 0, "conflicts": 0}
    assert sync(client, connected) == {"pushed": 0, "pulled": 0, "failed": 0, "conflicts": 0}
    # Push-only syncs must not move the cooldown window forward.
    assert client.get(f"{API}/calendar/status", headers=connected).json()["last_synced_at"] == last_synced

    # Let 3 minutes "pass" by moving the last sync back, so the real 2-minute check is exercised.
    db.execute(update(CalendarConnection).values(
        last_synced_at=CalendarConnection.last_synced_at - timedelta(minutes=3)))
    db.commit()
    assert sync(client, connected)["pulled"] == 1


def test_first_pull_after_turning_on_two_way_ignores_cooldown(client, connected, google, monkeypatch):
    monkeypatch.setattr(calendar_sync, "PULL_COOLDOWN", timedelta(minutes=2))
    create_event(client, connected)
    sync(client, connected)  # one-way: sets last_synced_at without ever pulling

    google.add_on_google("Từ Google", datetime(2026, 11, 3, 18, 0, tzinfo=TZ))
    two_way(client, connected)
    assert sync(client, connected)["pulled"] == 1


def test_conflict_keep_google_then_keep_local(client, connected, google):
    two_way(client, connected)
    event = create_event(client, connected)
    sync(client, connected)
    google_id = uuid.UUID(event["id"]).hex
    url = f"{API}/events/{event['id']}"

    google.edit_on_google(google_id, summary="Bản Google")
    client.patch(url, json={"title": "Bản local"}, headers=connected)
    assert sync(client, connected) == {"pushed": 0, "pulled": 0, "failed": 0, "conflicts": 1}
    [conflict] = client.get(f"{API}/calendar/conflicts", headers=connected).json()["items"]
    assert conflict["local"]["title"] == "Bản local"
    assert conflict["google"]["title"] == "Bản Google"
    assert client.get(f"{API}/calendar/status", headers=connected).json()["conflict_count"] == 1

    resolve = f"{API}/calendar/conflicts/{conflict['id']}/resolve"
    kept = client.post(resolve, json={"keep": "google"}, headers=connected).json()
    assert kept["title"] == "Bản Google"
    assert kept["sync_status"] == "synced"
    again = client.post(resolve, json={"keep": "local"}, headers=connected)
    assert again.status_code == 409

    google.edit_on_google(google_id, summary="Google lần 2")
    client.patch(url, json={"title": "Local lần 2"}, headers=connected)
    assert sync(client, connected)["conflicts"] == 1
    [conflict] = client.get(f"{API}/calendar/conflicts", headers=connected).json()["items"]
    kept = client.post(f"{API}/calendar/conflicts/{conflict['id']}/resolve", json={"keep": "local"},
                       headers=connected).json()
    assert kept["sync_status"] == "pending"
    assert sync(client, connected) == {"pushed": 1, "pulled": 0, "failed": 0, "conflicts": 0}
    assert google.events()[0]["summary"] == "Local lần 2"


def test_disconnect_keeps_local_events(client, connected, google):
    event = create_event(client, connected)
    sync(client, connected)
    assert client.delete(f"{API}/calendar/connection", headers=connected).status_code == 204
    assert google.revoked_tokens == ["google-refresh-token"]
    assert client.get(f"{API}/calendar/status", headers=connected).json()["connected"] is False
    assert get_event(client, connected, event)["sync_status"] == "not_synced"


def test_revoked_access_and_google_outage(client, connected, google):
    create_event(client, connected)
    google.revoked = True
    response = client.post(f"{API}/calendar/sync", headers=connected)
    assert (response.status_code, response.json()["code"]) == (403, "GOOGLE_SCOPE_MISSING")
    google.revoked = False
    google.down = True
    response = client.post(f"{API}/calendar/sync", headers=connected)
    assert (response.status_code, response.json()["code"]) == (503, "GOOGLE_UNAVAILABLE")


def test_settings_move_to_another_calendar(client, connected, google):
    google.calendars["study"] = {}
    event = create_event(client, connected)
    sync(client, connected)
    response = client.patch(f"{API}/calendar/settings", json={"calendar_id": "study"}, headers=connected)
    assert response.json()["calendar_id"] == "study"
    assert get_event(client, connected, event)["sync_status"] == "pending"
    sync(client, connected)
    assert [e["summary"] for e in google.events("study")] == ["Họp nhóm"]

    unknown = client.patch(f"{API}/calendar/settings", json={"calendar_id": "nope"}, headers=connected)
    assert unknown.status_code == 422


def test_webhook_triggers_a_pull(client, connected, google, monkeypatch):
    monkeypatch.setattr(Config, "WEBHOOK_BASE_URL", "https://recolly.example")
    two_way(client, connected)
    sync(client, connected)
    [(channel_id, resource_id)] = google.channels.items()
    headers = {"X-Goog-Channel-ID": channel_id, "X-Goog-Resource-ID": resource_id,
               "X-Goog-Resource-State": "exists", "X-Goog-Channel-Token": channel_token(channel_id)}

    google.add_on_google("Từ Google", datetime(2026, 11, 3, 18, 0, tzinfo=TZ))
    assert client.post(f"{API}/calendar/webhook", headers=headers).status_code == 200
    google.add_on_google("Token sai", datetime(2026, 11, 4, 18, 0, tzinfo=TZ))
    forged = {**headers, "X-Goog-Channel-Token": "wrong"}
    assert client.post(f"{API}/calendar/webhook", headers=forged).status_code == 200
    assert client.post(f"{API}/calendar/webhook").status_code == 200

    titles = [e["title"] for e in client.get(f"{API}/events", params=NOVEMBER, headers=connected).json()["items"]]
    assert titles == ["Từ Google"]


def test_daily_job_pulls_for_users_without_a_live_channel(client, connected, google):
    from app.jobs.calendar_maintenance import run_calendar_maintenance

    two_way(client, connected)  # no WEBHOOK_BASE_URL: no channel, so the job must pull
    google.add_on_google("Từ Google", datetime(2026, 11, 3, 18, 0, tzinfo=TZ))
    assert run_calendar_maintenance(google) == {"pulled": 1}
    titles = [e["title"] for e in client.get(f"{API}/events", params=NOVEMBER, headers=connected).json()["items"]]
    assert titles == ["Từ Google"]


def test_daily_job_renews_only_channels_close_to_expiry(client, connected, google, monkeypatch, db):
    from app.jobs.calendar_maintenance import run_calendar_maintenance

    monkeypatch.setattr(Config, "WEBHOOK_BASE_URL", "https://recolly.example")
    two_way(client, connected)
    [first_channel] = google.channels
    assert run_calendar_maintenance(google) == {"channel_ok": 1}
    assert list(google.channels) == [first_channel]

    # 6.5 days later the 7-day channel is inside the 1-day renewal window.
    db.execute(update(CalendarConnection).values(
        channel_expires_at=CalendarConnection.channel_expires_at - timedelta(days=6, hours=12)))
    db.commit()
    assert run_calendar_maintenance(google) == {"channel_ok": 1}
    [renewed] = google.channels
    assert renewed != first_channel


def test_daily_job_skips_a_revoked_user_and_keeps_going(client, connected, google):
    from app.jobs.calendar_maintenance import run_calendar_maintenance

    two_way(client, connected)
    google.revoked = True
    assert run_calendar_maintenance(google) == {"failed": 1}


def class_series_on_google(client, headers, google):
    """Save SUBJECT (Wednesdays 07:30) with two-way sync on and push it; returns Google's series."""
    two_way(client, headers)
    client.post(f"{API}/timetable", json={"subjects": [SUBJECT]}, headers=headers)
    sync(client, headers)
    [series] = google.events()
    return series


def test_two_way_pulls_one_moved_and_one_cancelled_class(client, connected, google):
    series = class_series_on_google(client, connected, google)
    moved = google.add_on_google("Học bù CTDL", datetime(2026, 11, 12, 14, 0, tzinfo=TZ), 135,
                                 recurringEventId=series["id"],
                                 originalStartTime={"dateTime": "2026-11-11T07:30:00+07:00"})
    google.add_on_google("Cấu trúc dữ liệu", datetime(2026, 11, 18, 7, 30, tzinfo=TZ), 135, status="cancelled",
                         recurringEventId=series["id"],
                         originalStartTime={"dateTime": "2026-11-18T07:30:00+07:00"})
    assert sync(client, connected) == {"pushed": 0, "pulled": 2, "failed": 0, "conflicts": 0}

    def classes_of_two_weeks():
        events = client.get(f"{API}/events", headers=connected, params={
            "from": "2026-11-09T00:00:00+07:00", "to": "2026-11-23T00:00:00+07:00", "kind": "class"}).json()
        return [(e["title"], e["start_at"]) for e in events["items"]]

    assert classes_of_two_weeks() == [("Học bù CTDL", "2026-11-12T14:00:00+07:00")]
    google.edit_on_google(moved["id"], summary="Học bù CTDL - C2.01")
    assert sync(client, connected)["pulled"] == 1
    assert classes_of_two_weeks() == [("Học bù CTDL - C2.01", "2026-11-12T14:00:00+07:00")]
    # One changed occurrence leaves the timetable as it was.
    [subject] = client.get(f"{API}/timetable", headers=connected).json()["items"]
    assert subject["day_of_week"] == 3


def test_class_series_moved_on_google_moves_the_subject(client, connected, google):
    series = class_series_on_google(client, connected, google)
    google.edit_on_google(series["id"], summary="CTDL", location="C2.01",
                          start={"dateTime": "2026-09-10T13:00:00+07:00"},
                          end={"dateTime": "2026-09-10T15:15:00+07:00"},
                          recurrence=["RRULE:FREQ=WEEKLY;BYDAY=TH;UNTIL=20261220T165959Z"])
    assert sync(client, connected)["pulled"] == 1
    [subject] = client.get(f"{API}/timetable", headers=connected).json()["items"]
    assert (subject["name"], subject["room"], subject["day_of_week"]) == ("CTDL", "C2.01", 4)
    assert (subject["start_time"][:5], subject["end_time"][:5]) == ("13:00", "15:15")


def test_only_a_todo_with_a_fixed_slot_becomes_an_event(client, connected, google):
    def summaries():
        return sorted(e["summary"] for e in google.events())

    todo = client.post(f"{API}/todos", json={"title": "Nộp báo cáo", "category": "assignment",
                                             "deadline_at": "2026-11-20T23:59:00+07:00"}, headers=connected).json()
    assert todo["difficulty"] == 5  # default of its category
    create_event(client, connected, title="Nộp báo cáo", kind="study", todo_id=todo["id"])
    assert sync(client, connected)["pushed"] == 1
    assert summaries() == ["Nộp báo cáo"]  # the study block; a deadline alone is not an event

    url = f"{API}/todos/{todo['id']}"
    client.patch(url, json={"title": "Báo cáo cuối kỳ"}, headers=connected)
    assert sync(client, connected)["pushed"] == 1
    assert summaries() == ["Báo cáo cuối kỳ"]  # the study block follows the new title

    client.patch(url, json={"start_at": "2026-11-19T08:00:00+07:00", "end_at": "2026-11-19T10:00:00+07:00"},
                 headers=connected)
    assert sync(client, connected)["pushed"] == 1
    assert summaries() == ["Báo cáo cuối kỳ", "Báo cáo cuối kỳ"]
    slot = next(e for e in google.events() if e["start"]["dateTime"].startswith("2026-11-19T08:00"))
    assert slot["end"]["dateTime"] == "2026-11-19T10:00:00+07:00"

    client.patch(url, json={"status": "done"}, headers=connected)
    assert sync(client, connected)["pushed"] == 1
    assert summaries() == ["Báo cáo cuối kỳ"]

    client.patch(url, json={"status": "todo"}, headers=connected)
    client.delete(url, headers=connected)
    sync(client, connected)
    assert summaries() == ["Báo cáo cuối kỳ"]  # deleting the todo removes its own slot, not study blocks


def settings(client, headers, **body):
    response = client.patch(f"{API}/calendar/settings", json=body, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def test_sync_modes(client, connected, google):
    status = client.get(f"{API}/calendar/status", headers=connected).json()
    assert (status["sync_mode"], status["calendar_id"]) == ("push", "primary")  # default: one-way

    event = create_event(client, connected)
    sync(client, connected)
    google.edit_on_google(uuid.UUID(event["id"]).hex, summary="Sửa trên Google")
    assert sync(client, connected)["pulled"] == 0  # push mode never pulls
    assert get_event(client, connected, event)["title"] == "Họp nhóm"

    assert settings(client, connected, sync_mode="off")["two_way_sync"] is False
    response = client.post(f"{API}/calendar/sync", headers=connected)
    assert (response.status_code, response.json()["code"]) == (409, "CALENDAR_SYNC_OFF")

    assert settings(client, connected, sync_mode="two_way")["two_way_sync"] is True
    assert sync(client, connected)["pulled"] == 1
    assert get_event(client, connected, event)["title"] == "Sửa trên Google"
    assert settings(client, connected, two_way_sync=False)["sync_mode"] == "push"  # deprecated flag still works


def test_a_new_link_writes_to_its_own_recolly_calendar(client, auth, google):
    google.add_grant("code", sub="sub", email="sv@gmail.com", calendar=True, app_calendar=True)
    status = client.post(f"{API}/calendar/connection", json={"server_auth_code": "code"}, headers=auth).json()
    assert status["calendar_id"].startswith("recolly")
    create_event(client, auth)
    sync(client, auth)
    assert google.events() == [] and len(google.events(status["calendar_id"])) == 1


def test_changes_to_different_fields_merge_without_a_conflict(client, connected, google):
    two_way(client, connected)
    event = create_event(client, connected)
    sync(client, connected)
    google.edit_on_google(uuid.UUID(event["id"]).hex, location="Phòng C2.01")
    client.patch(f"{API}/events/{event['id']}", json={"title": "Họp lớp"}, headers=connected)

    assert sync(client, connected) == {"pushed": 1, "pulled": 1, "failed": 0, "conflicts": 0}
    merged = get_event(client, connected, event)
    assert (merged["title"], merged["location"], merged["sync_status"]) == ("Họp lớp", "Phòng C2.01", "synced")
    [item] = google.events()
    assert (item["summary"], item["location"]) == ("Họp lớp", "Phòng C2.01")


@pytest.mark.parametrize(("policy", "title"), [("google", "Bản Google"), ("local", "Bản local"),
                                               ("latest", "Bản Google")])
def test_conflict_policy_decides_when_both_sides_changed_the_same_field(client, connected, google, policy, title):
    two_way(client, connected)
    settings(client, connected, conflict_policy=policy)
    event = create_event(client, connected)
    sync(client, connected)
    client.patch(f"{API}/events/{event['id']}", json={"title": "Bản local"}, headers=connected)
    google.edit_on_google(uuid.UUID(event["id"]).hex, summary="Bản Google")  # edited last

    assert sync(client, connected)["conflicts"] == 0
    assert get_event(client, connected, event)["title"] == title
    assert google.events()[0]["summary"] == title


def test_changes_are_pushed_automatically_after_commit(client, connected, google, monkeypatch):
    from app.service import calendar_autopush

    monkeypatch.setattr(calendar_autopush, "ENABLED", True)
    monkeypatch.setattr(calendar_autopush, "run", lambda user_id: calendar_autopush.push_now(user_id, google))
    event = create_event(client, connected)
    assert [e["summary"] for e in google.events()] == ["Họp nhóm"]
    assert get_event(client, connected, event)["sync_status"] == "synced"

    settings(client, connected, sync_mode="off")
    client.patch(f"{API}/events/{event['id']}", json={"title": "Đổi khi tắt sync"}, headers=connected)
    assert google.events()[0]["summary"] == "Họp nhóm"  # paused
    settings(client, connected, sync_mode="push")  # turning it back on pushes what waited
    assert google.events()[0]["summary"] == "Đổi khi tắt sync"


def test_google_busy_times_are_reported_as_clashes(client, connected, google):
    google.add_on_google("Họp CLB", datetime(2026, 11, 2, 19, 30, tzinfo=TZ))
    event = create_event(client, connected)  # 19:00-20:00 the same evening
    [clash] = event["clashes"]
    assert (clash["title"], clash["source"], clash["event_id"], clash["movable"]) == ("Họp CLB", "google", None, False)


def test_a_412_merge_is_pushed_in_the_same_sync(client, connected, google, monkeypatch):
    two_way(client, connected)
    event = create_event(client, connected)
    sync(client, connected)
    google.edit_on_google(uuid.UUID(event["id"]).hex, location="Phòng C2.01")
    client.patch(f"{API}/events/{event['id']}", json={"title": "Họp lớp"}, headers=connected)
    # A push-only run (the automatic push) meets Google's newer etag: 412 → merge → push again.
    from app.db.session import SessionLocal
    from app.models.user import User

    with SessionLocal() as db:
        user = db.get(User, uuid.UUID(client.get(f"{API}/users/me", headers=connected).json()["id"]))
        calendar_sync.sync(db, user, google, pull=False)
        db.commit()
    [item] = google.events()
    assert (item["summary"], item["location"]) == ("Họp lớp", "Phòng C2.01")
    assert get_event(client, connected, event)["sync_status"] == "synced"


def test_disconnect_deletes_only_the_calendar_the_app_created(client, auth, google):
    google.add_grant("code", sub="sub", email="sv@gmail.com", calendar=True, app_calendar=True)
    calendar_id = client.post(f"{API}/calendar/connection", json={"server_auth_code": "code"},
                              headers=auth).json()["calendar_id"]
    assert client.delete(f"{API}/calendar/connection", headers=auth).status_code == 204
    assert calendar_id not in google.calendars and "primary" in google.calendars
