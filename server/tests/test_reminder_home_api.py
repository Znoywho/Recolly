from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

from tests.conftest import bearer, make_user

API = "/api/v1"
TZ = ZoneInfo("Asia/Ho_Chi_Minh")
DEFAULTS = {
    "bedtime_reminder_enabled": True, "bedtime_reminder_minutes_before": 30,
    "deadline_reminder_enabled": True, "deadline_reminder_hours_before": [24, 2],
    "kss_prompt_enabled": True, "kss_prompts_per_day": 4,
    "kss_prompt_window": {"start": "08:00", "end": "23:00"}, "sleep_confirm_enabled": True,
    "motivation_enabled": True, "quiet_hours": None,
}


def test_reminder_settings(client, auth):
    assert client.get(f"{API}/reminder-settings", headers=auth).json() == DEFAULTS
    saved = {**DEFAULTS, "bedtime_reminder_minutes_before": 45, "deadline_reminder_hours_before": [48, 3],
             "quiet_hours": {"start": "23:00", "end": "07:00"}}
    response = client.put(f"{API}/reminder-settings", json=saved, headers=auth)
    assert response.status_code == 200, response.text
    assert response.json() == saved
    assert client.get(f"{API}/reminder-settings", headers=auth).json() == saved


@pytest.mark.parametrize("override", [
    {"deadline_reminder_hours_before": [2, 2]},
    {"deadline_reminder_hours_before": [200]},
    {"kss_prompts_per_day": 9},
    {"quiet_hours": {"start": "23:00"}},
])
def test_reminder_settings_validation(client, auth, override):
    response = client.put(f"{API}/reminder-settings", json={**DEFAULTS, **override}, headers=auth)
    assert response.status_code == 422


def test_devices(client, auth, db):
    assert client.post(f"{API}/devices", json={"fcm_token": "token-1"}, headers=auth).status_code == 204
    other = bearer(make_user(db, email="other@example.com").id)
    # Registering a known token moves it to the current user.
    assert client.post(f"{API}/devices", json={"fcm_token": "token-1"}, headers=other).status_code == 204
    from app.models.notification import Device
    db.expire_all()
    assert db.query(Device).count() == 1
    assert client.delete(f"{API}/devices/token-1", headers=other).status_code == 204
    assert client.delete(f"{API}/devices/unknown", headers=other).status_code == 204
    assert db.query(Device).count() == 0


def test_quotes(client, auth):
    quote = client.get(f"{API}/quotes/random", params={"context": "sleep"}, headers=auth).json()
    assert (quote["source"], quote["context"]) == ("fallback", "sleep")
    assert quote["text"]
    assert client.get(f"{API}/quotes/random", headers=auth).json()["context"] == "general"
    assert client.get(f"{API}/quotes/random", params={"context": "nope"}, headers=auth).status_code == 422


def test_home_overview(client, auth):
    assert client.get(f"{API}/home", headers=auth).json()["code"] == "HEALTH_PROFILE_NOT_FOUND"
    client.put(f"{API}/health-profile", headers=auth,
               json={"usual_sleep_time": "23:00", "usual_wake_time": "06:30"})
    today = datetime.now(TZ).date()
    late = datetime.combine(today, time(23, 30), TZ) - timedelta(minutes=5)
    client.post(f"{API}/events", headers=auth, json={
        "title": "Họp nhóm", "start_at": late.isoformat(), "end_at": (late + timedelta(minutes=5)).isoformat()})
    for title, days in (("Sau", 5), ("Gần", 1), ("Giữa", 3), ("Xa", 9)):
        client.post(f"{API}/todos", headers=auth, json={
            "title": title, "deadline_at": (datetime.now(TZ) + timedelta(days=days)).isoformat()})

    response = client.get(f"{API}/home", headers=auth)
    assert response.status_code == 200, response.text
    home = response.json()
    assert home["date"] == today.isoformat()
    assert [e["title"] for e in home["today_events"]] == ["Họp nhóm"]
    assert [t["title"] for t in home["upcoming_todos"]] == ["Gần", "Giữa", "Sau"]
    assert home["tonight"]["night_of"] == today.isoformat()
    assert home["sleep_debt_7d_minutes"] == 0
    assert home["last_night"] is None
    assert home["needs_sleep_confirmation"] is False
    assert home["kss_checkin_due"] is False
    assert home["now"]["time"].endswith("+07:00")
    assert home["model"]["kss_days"] == 0
