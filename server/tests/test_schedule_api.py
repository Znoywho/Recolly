from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.service import scheduler

API = "/api/v1"
TZ = ZoneInfo("Asia/Ho_Chi_Minh")


def today():
    return datetime.now(TZ).date()


def at(day, hour, minute=0):
    return datetime.combine(day, time(hour, minute), TZ)


def parse(value):
    return datetime.fromisoformat(value)


def minutes(block):
    return (parse(block["end_at"]) - parse(block["start_at"])).total_seconds() / 60


def prepare(client, headers):
    """Sleep 23:00–06:30 every night and a 07:30–11:30 class tomorrow; returns tomorrow."""
    profile = client.put(f"{API}/health-profile", headers=headers, json={
        "usual_sleep_time": "23:00", "usual_wake_time": "06:30", "chronotype": "bear"})
    assert profile.status_code == 200, profile.text
    tomorrow = today() + timedelta(days=1)
    client.post(f"{API}/timetable", headers=headers, json={"subjects": [{
        "name": "Giải tích", "day_of_week": tomorrow.isoweekday(), "start_time": "07:30",
        "end_time": "11:30", "start_date": (today() - timedelta(days=7)).isoformat(),
        "end_date": (today() + timedelta(days=30)).isoformat()}]})
    return tomorrow


def add_todo(client, headers, **body):
    response = client.post(f"{API}/todos", json={"title": "Ôn Giải tích", **body}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def generate(client, headers, first, last, **body):
    response = client.post(f"{API}/schedule/generate", headers=headers,
                           json={"from": first.isoformat(), "to": last.isoformat(), **body})
    assert response.status_code == 200, response.text
    return response.json()


def overlaps(block, start, end):
    return parse(block["start_at"]) < end and start < parse(block["end_at"])


def test_blocks_respect_every_constraint(client, auth):
    tomorrow = prepare(client, auth)
    deadline = at(tomorrow + timedelta(days=2), 23, 59)
    todo = add_todo(client, auth, deadline_at=deadline.isoformat(), estimated_minutes=180,
                    difficulty=4, priority="high")
    suggestion = generate(client, auth, tomorrow, tomorrow + timedelta(days=1))

    assert suggestion["solver_status"] in ("OPTIMAL", "FEASIBLE")
    assert suggestion["unscheduled"] == []
    study = [b for b in suggestion["blocks"] if b["kind"] == "study"]
    assert sum(minutes(b) for b in study) == 180
    for block in study:
        start, end = parse(block["start_at"]), parse(block["end_at"])
        assert block["todo_id"] == todo["id"]
        assert not overlaps(block, at(tomorrow, 7, 30), at(tomorrow, 11, 30))  # class
        assert start.time() >= time(7, 0) and end.time() <= time(22, 0)        # wake + 30 min, bed − 60 min
        for day in (tomorrow, tomorrow + timedelta(days=1)):
            assert not overlaps(block, at(day, 11, 30), at(day, 13))              # lunch
            assert not overlaps(block, at(day, 18), at(day, 19))                  # dinner
        assert end <= deadline
        assert 1 <= block["predicted_kss"] <= 9
    for earlier, later in zip(study, study[1:]):
        assert parse(later["start_at"]) - parse(earlier["end_at"]) >= timedelta(minutes=30)
    assert [b["index"] for b in suggestion["blocks"]] == list(range(len(suggestion["blocks"])))
    assert sum(b["kind"] == "bedtime" for b in suggestion["blocks"]) == 2
    assert suggestion["stats"]["study_minutes"] == 180
    assert 0 <= suggestion["stats"]["golden_hour_ratio"] <= 1
    assert suggestion["model"]["personalization_level"] == "prior_only"
    assert suggestion["from"] == tomorrow.isoformat()


def test_apply_creates_events_once(client, auth):
    tomorrow = prepare(client, auth)
    todo = add_todo(client, auth, deadline_at=at(tomorrow + timedelta(days=1), 23, 59).isoformat(),
                    estimated_minutes=90)
    suggestion = generate(client, auth, tomorrow, tomorrow)
    url = f"{API}/schedule/apply"

    bad = client.post(url, json={"suggestion_id": suggestion["suggestion_id"], "block_indexes": [99]},
                      headers=auth)
    assert bad.status_code == 422
    applied = client.post(url, json={"suggestion_id": suggestion["suggestion_id"]}, headers=auth)
    assert applied.status_code == 201, applied.text
    events = applied.json()["events"]
    assert {e["kind"] for e in events} == {"study", "bedtime"}
    assert all(e["source"] == "scheduler" for e in events)
    assert applied.json()["sync"] is None
    assert client.get(f"{API}/todos/{todo['id']}", headers=auth).json()["scheduled_minutes"] == 90

    again = client.post(url, json={"suggestion_id": suggestion["suggestion_id"]}, headers=auth)
    assert (again.status_code, again.json()["code"]) == (404, "SUGGESTION_NOT_FOUND")
    [skipped] = generate(client, auth, tomorrow, tomorrow)["unscheduled"]
    assert (skipped["todo_id"], skipped["reason"]) == (todo["id"], "ALREADY_SCHEDULED")


def test_apply_a_subset_and_push_to_google(client, connected, google):
    tomorrow = prepare(client, connected)
    add_todo(client, connected, deadline_at=at(tomorrow + timedelta(days=1), 23, 59).isoformat(),
             estimated_minutes=90)
    suggestion = generate(client, connected, tomorrow, tomorrow)
    [study] = [b for b in suggestion["blocks"] if b["kind"] == "study"]
    applied = client.post(f"{API}/schedule/apply", headers=connected, json={
        "suggestion_id": suggestion["suggestion_id"], "block_indexes": [study["index"]],
        "sync_to_google": True}).json()
    assert [e["kind"] for e in applied["events"]] == ["study"]
    assert applied["sync"]["failed"] == 0
    assert "Ôn Giải tích" in [e["summary"] for e in google.events()]


def test_unscheduled_reasons(client, auth):
    tomorrow = prepare(client, auth)
    two_days = at(tomorrow + timedelta(days=1), 23, 59).isoformat()
    no_deadline = add_todo(client, auth, title="Không deadline", estimated_minutes=60)
    no_estimate = add_todo(client, auth, title="Không ước lượng", deadline_at=two_days)
    late = add_todo(client, auth, title="Trễ hạn", estimated_minutes=60,
                    deadline_at=at(today() - timedelta(days=1), 23, 59).isoformat())
    big = add_todo(client, auth, title="Đồ án", estimated_minutes=600, deadline_at=two_days)

    suggestion = generate(client, auth, tomorrow, tomorrow + timedelta(days=1))
    reasons = {u["todo_id"]: (u["reason"], u["missing_minutes"]) for u in suggestion["unscheduled"]}
    assert reasons[no_deadline["id"]] == ("MISSING_DEADLINE", 60)
    assert reasons[no_estimate["id"]] == ("MISSING_ESTIMATE", None)
    assert reasons[late["id"]] == ("DEADLINE_PASSED", 60)
    # 2 days x 240 min limit: 90 + 90 + 60 one day, 90 + 90 the other; 180 min do not fit.
    assert reasons[big["id"]] == ("DAILY_LIMIT_REACHED", 180)
    per_day = {}
    for block in suggestion["blocks"]:
        if block["kind"] == "study":
            day = parse(block["start_at"]).date()
            per_day[day] = per_day.get(day, 0) + minutes(block)
    assert max(per_day.values()) <= 240


def test_expired_suggestion(client, auth):
    tomorrow = prepare(client, auth)
    suggestion = generate(client, auth, tomorrow, tomorrow)
    import uuid
    scheduler._suggestions[uuid.UUID(suggestion["suggestion_id"])].expires_at = at(today(), 0)
    response = client.post(f"{API}/schedule/apply", json={"suggestion_id": suggestion["suggestion_id"]},
                           headers=auth)
    assert (response.status_code, response.json()["code"]) == (410, "SUGGESTION_EXPIRED")


@pytest.mark.parametrize("first, last, code", [(3, 1, "INVALID_RANGE"), (1, 16, "RANGE_TOO_LARGE")])
def test_range_errors(client, auth, first, last, code):
    prepare(client, auth)
    response = client.post(f"{API}/schedule/generate", headers=auth, json={
        "from": (today() + timedelta(days=first)).isoformat(),
        "to": (today() + timedelta(days=last)).isoformat()})
    assert (response.status_code, response.json()["code"]) == (400, code)


def test_needs_a_profile_and_known_todos(client, auth):
    body = {"from": today().isoformat(), "to": today().isoformat()}
    response = client.post(f"{API}/schedule/generate", json=body, headers=auth)
    assert response.json()["code"] == "HEALTH_PROFILE_NOT_FOUND"
    prepare(client, auth)
    import uuid
    response = client.post(f"{API}/schedule/generate", headers=auth,
                           json={**body, "todo_ids": [str(uuid.uuid4())]})
    assert response.json()["code"] == "TODO_NOT_FOUND"
