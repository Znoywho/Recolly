"""A fixed event saved over a CP-SAT study block moves the block; fixed vs fixed is only reported."""

from datetime import timedelta

from tests.test_calendar_api import no_pull_cooldown, sync, two_way  # noqa: F401 (autouse fixture)
from tests.test_schedule_api import API, add_todo, at, generate, overlaps, parse, prepare


def apply_one_block(client, headers):
    """Plan one 90-minute study block for the day after tomorrow and save it; returns the event."""
    day = prepare(client, headers) + timedelta(days=1)
    add_todo(client, headers, category="exam", deadline_at=at(day + timedelta(days=3), 22).isoformat(),
             estimated_minutes=90)
    suggestion = generate(client, headers, day, day)
    study = [b["index"] for b in suggestion["blocks"] if b["kind"] == "study"]
    applied = client.post(f"{API}/schedule/apply", headers=headers,
                          json={"suggestion_id": suggestion["suggestion_id"], "block_indexes": study}).json()
    [block] = applied["events"]
    return block


def test_a_fixed_event_moves_the_study_block_it_overlaps(client, auth):
    block = apply_one_block(client, auth)
    meeting = client.post(f"{API}/events", headers=auth, json={
        "title": "Họp CLB", "start_at": block["start_at"], "end_at": block["end_at"]}).json()

    assert meeting["clashes"] == []
    [moved] = meeting["rescheduled"]
    assert moved["kind"] == "study" and moved["todo_id"] == block["todo_id"]
    assert not overlaps(moved, parse(meeting["start_at"]), parse(meeting["end_at"]))
    assert client.get(f"{API}/events/{block['id']}", headers=auth).status_code == 404


def test_fixed_events_are_only_reported(client, auth):
    first = client.post(f"{API}/events", headers=auth, json={
        "title": "Làm thêm", "start_at": "2026-11-02T18:00:00+07:00", "end_at": "2026-11-02T21:00:00+07:00"}).json()
    second = client.post(f"{API}/events", headers=auth, json={
        "title": "Họp nhóm", "start_at": "2026-11-02T19:00:00+07:00", "end_at": "2026-11-02T20:00:00+07:00"}).json()
    [clash] = second["clashes"]
    assert (clash["event_id"], clash["movable"], second["rescheduled"]) == (first["id"], False, [])


def test_an_event_added_on_google_moves_the_study_block(client, connected, google):
    two_way(client, connected)
    block = apply_one_block(client, connected)
    sync(client, connected)
    google.add_on_google("Đi làm thêm", parse(block["start_at"]), 90)

    assert sync(client, connected)["pulled"] == 1
    assert client.get(f"{API}/events/{block['id']}", headers=connected).status_code == 404
    studies = client.get(f"{API}/events", headers=connected, params={
        "from": block["start_at"], "to": (parse(block["start_at"]) + timedelta(days=13)).isoformat(),
        "kind": "study"}).json()["items"]
    assert len(studies) == 1 and studies[0]["start_at"] != block["start_at"]


def test_applying_a_plan_while_sync_is_off_keeps_the_blocks(client, connected):
    client.patch(f"{API}/calendar/settings", json={"sync_mode": "off"}, headers=connected)
    day = prepare(client, connected) + timedelta(days=1)
    add_todo(client, connected, deadline_at=at(day + timedelta(days=3), 22).isoformat(), estimated_minutes=90)
    suggestion = generate(client, connected, day, day)
    response = client.post(f"{API}/schedule/apply", headers=connected,
                           json={"suggestion_id": suggestion["suggestion_id"], "sync_to_google": True})
    assert response.status_code == 201, response.text
    assert response.json()["sync"] is None
    assert {e["sync_status"] for e in response.json()["events"]} == {"pending"}  # pushed once sync is back on
