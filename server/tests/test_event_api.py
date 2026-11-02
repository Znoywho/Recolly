import uuid
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from tests.conftest import bearer, make_user

API = "/api/v1"
TZ = ZoneInfo("Asia/Ho_Chi_Minh")
NOVEMBER = {"from": "2026-11-01T00:00:00+07:00", "to": "2026-11-30T00:00:00+07:00"}


def event_body(**overrides):
    start = datetime(2026, 11, 2, 19, 0, tzinfo=TZ)  # a Monday
    body = {"title": "Họp nhóm", "start_at": start.isoformat(),
            "end_at": (start + timedelta(hours=1)).isoformat()}
    body.update(overrides)
    return body


def create(client, headers, **overrides):
    response = client.post(f"{API}/events", json=event_body(**overrides), headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def test_create_and_get(client, auth):
    event = create(client, auth)
    assert event["source"] == "manual"
    assert event["kind"] == "other"
    assert event["sync_status"] == "not_synced"
    assert event["start_at"] == "2026-11-02T19:00:00+07:00"
    assert event["occurrence_start"] is None
    assert client.get(f"{API}/events/{event['id']}", headers=auth).json() == event


def test_event_of_a_connected_user_is_pending(client, connected):
    assert create(client, connected)["sync_status"] == "pending"


@pytest.mark.parametrize("overrides", [
    {"end_at": "2026-11-02T18:00:00+07:00"},
    {"kind": "class"},
    {"rrule": "FREQ=SOMETIMES"},
    {"start_at": "2026-11-02T19:00:00"},  # no UTC offset
    {"title": ""},
])
def test_create_validation(client, auth, overrides):
    assert client.post(f"{API}/events", json=event_body(**overrides), headers=auth).status_code == 422


def test_unknown_todo(client, auth):
    response = client.post(f"{API}/events", json=event_body(todo_id=str(uuid.uuid4())), headers=auth)
    assert response.status_code == 404
    assert response.json()["code"] == "TODO_NOT_FOUND"


def test_list_expands_recurring_events(client, auth):
    gym = create(client, auth, title="Gym", rrule="FREQ=WEEKLY;BYDAY=MO,TH;UNTIL=20261115")
    assert gym["rrule"] == "FREQ=WEEKLY;BYDAY=MO,TH;UNTIL=20261115T165959Z"  # floating UNTIL -> UTC
    create(client, auth, title="One-off", start_at="2026-11-04T08:00:00+07:00",
           end_at="2026-11-04T09:00:00+07:00")

    items = client.get(f"{API}/events", params=NOVEMBER, headers=auth).json()["items"]
    assert [i["title"] for i in items] == ["Gym", "One-off", "Gym", "Gym", "Gym"]
    instances = [i for i in items if i["title"] == "Gym"]
    assert [i["start_at"] for i in instances] == [
        "2026-11-02T19:00:00+07:00", "2026-11-05T19:00:00+07:00",
        "2026-11-09T19:00:00+07:00", "2026-11-12T19:00:00+07:00",
    ]
    assert all(i["id"] == gym["id"] and i["occurrence_start"] == i["start_at"] for i in instances)
    assert instances[1]["end_at"] == "2026-11-05T20:00:00+07:00"


def test_list_filters_and_range_errors(client, auth):
    create(client, auth, kind="study")
    create(client, auth)
    study = client.get(f"{API}/events", params={**NOVEMBER, "kind": "study"}, headers=auth).json()
    assert [e["kind"] for e in study["items"]] == ["study"]

    backwards = client.get(f"{API}/events", headers=auth,
                           params={"from": "2026-11-02T00:00:00Z", "to": "2026-11-01T00:00:00Z"})
    assert backwards.status_code == 400
    assert backwards.json()["code"] == "INVALID_RANGE"
    too_long = client.get(f"{API}/events", headers=auth,
                          params={"from": "2026-11-01T00:00:00Z", "to": "2027-01-15T00:00:00Z"})
    assert too_long.json()["code"] == "RANGE_TOO_LARGE"


def test_update_and_delete(client, auth):
    event = create(client, auth, location="B1.02")
    url = f"{API}/events/{event['id']}"
    updated = client.patch(url, json={"title": "Họp lớp", "location": None}, headers=auth).json()
    assert updated["title"] == "Họp lớp"
    assert updated["location"] is None

    backwards = client.patch(url, json={"end_at": "2026-11-02T18:00:00+07:00"}, headers=auth)
    assert backwards.status_code == 400
    assert backwards.json()["code"] == "INVALID_RANGE"
    assert client.patch(url, json={"title": None}, headers=auth).status_code == 422
    assert client.patch(url, json={}, headers=auth).status_code == 422

    assert client.delete(url, headers=auth).status_code == 204
    assert client.get(url, headers=auth).json()["code"] == "EVENT_NOT_FOUND"


def test_events_of_other_users_are_not_found(client, auth, db):
    other = bearer(make_user(db, email="other@example.com").id)
    event = create(client, other)
    assert client.get(f"{API}/events/{event['id']}", headers=auth).status_code == 404
    assert client.delete(f"{API}/events/{event['id']}", headers=auth).status_code == 404
