import pytest

API = "/api/v1"


def test_get_and_update_me(client, auth):
    me = client.get(f"{API}/users/me", headers=auth).json()
    assert me["display_name"] == "Sinh Viên"

    response = client.patch(f"{API}/users/me", json={"display_name": None, "timezone": "Asia/Tokyo"},
                            headers=auth)
    assert response.status_code == 200
    updated = response.json()
    assert updated["display_name"] is None
    assert updated["timezone"] == "Asia/Tokyo"
    assert updated["created_at"].endswith("+09:00")  # responses use the user's timezone


@pytest.mark.parametrize("body", [{}, {"timezone": None}, {"timezone": "Mars/Base"}])
def test_update_me_validation(client, auth, body):
    assert client.patch(f"{API}/users/me", json=body, headers=auth).status_code == 422


def test_delete_me_revokes_google_and_removes_the_account(client, connected, google, db):
    from sqlalchemy import func, select

    from app.db.base import Base
    from tests.test_timetable_api import SUBJECT

    client.put(f"{API}/health-profile", json={"usual_sleep_time": "23:00", "usual_wake_time": "06:30"},
               headers=connected)
    client.post(f"{API}/timetable", json={"subjects": [SUBJECT]}, headers=connected)
    todo = client.post(f"{API}/todos", json={"title": "x"}, headers=connected).json()
    client.post(f"{API}/events", headers=connected, json={
        "title": "Ôn", "kind": "study", "todo_id": todo["id"],
        "start_at": "2026-11-03T09:00:00+07:00", "end_at": "2026-11-03T10:00:00+07:00"})
    client.post(f"{API}/sleep-logs", headers=connected, json={
        "sleep_at": "2026-11-02T23:00:00+07:00", "wake_at": "2026-11-03T06:30:00+07:00"})
    client.post(f"{API}/calendar/sync", headers=connected)
    client.post(f"{API}/devices", json={"fcm_token": "t"}, headers=connected)

    assert client.delete(f"{API}/users/me", headers=connected).status_code == 204
    assert google.revoked_tokens == ["google-refresh-token"]
    response = client.get(f"{API}/users/me", headers=connected)
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_INVALID"
    for table in Base.metadata.sorted_tables:
        assert db.scalar(select(func.count()).select_from(table)) == 0, table.name


def test_health(client):
    response = client.get(f"{API}/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "db": "ok", "redis": "down", "version": "1.0.0"}


def test_unknown_route_uses_the_error_body(client):
    response = client.get(f"{API}/nope")
    assert response.status_code == 404
    assert response.json()["code"] == "NOT_FOUND"
