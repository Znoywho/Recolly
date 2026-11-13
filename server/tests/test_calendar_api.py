import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

from app.config import Config
from app.core.security import channel_token
from tests.test_event_api import create as create_event
from tests.test_timetable_api import SUBJECT

API = "/api/v1"
TZ = ZoneInfo("Asia/Ho_Chi_Minh")
NOVEMBER = {"from": "2026-11-01T00:00:00+07:00", "to": "2026-11-30T00:00:00+07:00"}


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
        "connected": False, "google_email": None, "calendar_id": None, "two_way_sync": False,
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
