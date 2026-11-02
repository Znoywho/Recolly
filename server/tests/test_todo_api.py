import pytest

API = "/api/v1"


def create(client, headers, **body):
    response = client.post(f"{API}/todos", json={"title": "Bài tập lớn CTDL", **body}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def titles(page):
    return [t["title"] for t in page["items"]]


def test_create_with_defaults(client, auth):
    todo = create(client, auth)
    assert todo["category"] == "other"
    assert todo["priority"] == "medium"
    assert todo["status"] == "todo"
    assert todo["scheduled_minutes"] == 0
    assert todo["completed_at"] is None
    assert client.get(f"{API}/todos/{todo['id']}", headers=auth).json() == todo


@pytest.mark.parametrize("body", [
    {"start_at": "2026-11-02T10:00:00+07:00", "end_at": "2026-11-02T09:00:00+07:00"},
    {"estimated_minutes": 0},
    {"difficulty": 6},
    {"deadline_at": "2026-11-02T10:00:00"},
    {"category": "party"},
])
def test_create_validation(client, auth, body):
    assert client.post(f"{API}/todos", json={"title": "x", **body}, headers=auth).status_code == 422


def test_list_sorts_filters_and_pages(client, auth):
    create(client, auth, title="No deadline", priority="high")
    create(client, auth, title="Late", deadline_at="2026-11-20T23:59:00+07:00", category="exam")
    create(client, auth, title="Soon", deadline_at="2026-11-05T23:59:00+07:00", priority="low")
    done = create(client, auth, title="Done", deadline_at="2026-11-01T23:59:00+07:00")
    client.patch(f"{API}/todos/{done['id']}", json={"status": "done"}, headers=auth)

    def page(**params):
        response = client.get(f"{API}/todos", params=params, headers=auth)
        assert response.status_code == 200, response.text
        return response.json()

    assert titles(page()) == ["Done", "Soon", "Late", "No deadline"]  # no deadline sorts last
    assert titles(page(sort="-deadline_at")) == ["Late", "Soon", "Done", "No deadline"]
    assert titles(page(sort="-priority"))[0] == "No deadline"
    assert titles(page(status=["todo", "in_progress"])) == ["Soon", "Late", "No deadline"]
    assert titles(page(category="exam")) == ["Late"]
    assert titles(page(due_before="2026-11-10T00:00:00+07:00", due_after="2026-11-02T00:00:00+07:00")) == ["Soon"]

    first = page(limit=3)
    assert titles(first) == ["Done", "Soon", "Late"]
    second = page(limit=3, cursor=first["next_cursor"])
    assert titles(second) == ["No deadline"]
    assert second["next_cursor"] is None
    assert client.get(f"{API}/todos", params={"cursor": "garbage"}, headers=auth).status_code == 400


def test_status_drives_completed_at(client, auth):
    todo = create(client, auth)
    url = f"{API}/todos/{todo['id']}"
    done = client.patch(url, json={"status": "done"}, headers=auth).json()
    assert done["completed_at"] is not None
    reopened = client.patch(url, json={"status": "in_progress"}, headers=auth).json()
    assert reopened["completed_at"] is None

    assert client.patch(url, json={"title": None}, headers=auth).status_code == 422
    backwards = client.patch(url, json={"start_at": "2026-11-02T10:00:00+07:00",
                                        "end_at": "2026-11-02T09:00:00+07:00"}, headers=auth)
    assert backwards.status_code == 400


def test_scheduled_minutes_and_delete_keeps_study_events(client, auth):
    todo = create(client, auth, deadline_at="2026-11-20T23:59:00+07:00", estimated_minutes=240)
    event = client.post(f"{API}/events", headers=auth, json={
        "title": "Ôn CTDL", "kind": "study", "todo_id": todo["id"],
        "start_at": "2026-11-03T09:00:00+07:00", "end_at": "2026-11-03T10:30:00+07:00"}).json()
    assert client.get(f"{API}/todos/{todo['id']}", headers=auth).json()["scheduled_minutes"] == 90

    assert client.delete(f"{API}/todos/{todo['id']}", headers=auth).status_code == 204
    assert client.get(f"{API}/events/{event['id']}", headers=auth).json()["todo_id"] is None
    assert client.get(f"{API}/todos/{todo['id']}", headers=auth).json()["code"] == "TODO_NOT_FOUND"
