import pytest

API = "/api/v1"
SUBJECT = {
    "name": "Cấu trúc dữ liệu",
    "code": "IT003",
    "room": "B1.02",
    "lecturer": "Nguyễn Văn B",
    "day_of_week": 3,  # Wednesday
    "start_time": "07:30",
    "end_time": "09:45",
    "start_date": "2026-09-07",
    "end_date": "2026-12-20",
    "color": "#FF5C8A",
}
FIRST_HALF_OF_NOVEMBER = {"from": "2026-11-01T00:00:00+07:00", "to": "2026-11-15T00:00:00+07:00",
                          "kind": "class"}


def create(client, headers, *subjects, replace=False):
    response = client.post(f"{API}/timetable", headers=headers,
                           json={"subjects": list(subjects or [SUBJECT]), "replace_existing": replace})
    assert response.status_code == 201, response.text
    return response.json()["items"]


def class_events(client, headers):
    return client.get(f"{API}/events", params=FIRST_HALF_OF_NOVEMBER, headers=headers).json()["items"]


def test_subject_becomes_a_weekly_class_event(client, auth):
    [subject] = create(client, auth)
    assert subject["start_time"] == "07:30"
    assert subject["color"] == "#FF5C8A"

    events = class_events(client, auth)
    assert [e["start_at"] for e in events] == ["2026-11-04T07:30:00+07:00", "2026-11-11T07:30:00+07:00"]
    assert events[0]["end_at"] == "2026-11-04T09:45:00+07:00"
    assert events[0]["subject_id"] == subject["id"]
    assert events[0]["location"] == "B1.02"
    assert events[0]["description"] == "Mã HP: IT003\nGiảng viên: Nguyễn Văn B"
    assert client.get(f"{API}/timetable", headers=auth).json()["items"] == [subject]


def test_editing_a_subject_moves_its_event(client, auth):
    [subject] = create(client, auth)
    url = f"{API}/timetable/{subject['id']}"
    response = client.patch(url, json={"day_of_week": 5, "start_time": "13:00", "end_time": "15:00"},
                            headers=auth)
    assert response.status_code == 200
    assert [e["start_at"] for e in class_events(client, auth)] == [
        "2026-11-06T13:00:00+07:00", "2026-11-13T13:00:00+07:00"]

    backwards = client.patch(url, json={"end_time": "12:00"}, headers=auth)
    assert backwards.status_code == 400
    assert backwards.json()["code"] == "INVALID_RANGE"


def test_delete_and_replace(client, auth):
    [old] = create(client, auth)
    [new] = create(client, auth, {**SUBJECT, "name": "Giải tích", "day_of_week": 2}, replace=True)
    assert [s["id"] for s in client.get(f"{API}/timetable", headers=auth).json()["items"]] == [new["id"]]
    assert {e["title"] for e in class_events(client, auth)} == {"Giải tích"}

    assert client.delete(f"{API}/timetable/{new['id']}", headers=auth).status_code == 204
    assert class_events(client, auth) == []
    assert client.delete(f"{API}/timetable/{old['id']}", headers=auth).json()["code"] == "SUBJECT_NOT_FOUND"


@pytest.mark.parametrize("override", [
    {"start_time": "7:30"},
    {"end_time": "07:00"},
    {"end_date": "2026-09-01"},
    {"day_of_week": 8},
    {"color": "red"},
])
def test_subject_validation(client, auth, override):
    response = client.post(f"{API}/timetable", json={"subjects": [{**SUBJECT, **override}]}, headers=auth)
    assert response.status_code == 422
