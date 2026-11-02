from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

API = "/api/v1"
TZ = ZoneInfo("Asia/Ho_Chi_Minh")
CONTRACT_MCTQ = {"sleep_onset_work": "00:30", "sleep_end_work": "06:30",
                 "sleep_onset_free": "01:45", "sleep_end_free": "10:00", "work_days": 5}
PROFILE = {"usual_sleep_time": "00:00", "usual_wake_time": "06:30", "sleep_need_hours": 8,
           "morning_prep_minutes": 60, "mctq": CONTRACT_MCTQ}


def today():
    return datetime.now(TZ).date()


def at(day, hour, minute=0):
    return datetime.combine(day, time(hour, minute), TZ)


def put_profile(client, headers, **overrides):
    response = client.put(f"{API}/health-profile", json={**PROFILE, **overrides}, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def add_log(client, headers, sleep_at, wake_at, **body):
    return client.post(f"{API}/sleep-logs", headers=headers,
                       json={"sleep_at": sleep_at.isoformat(), "wake_at": wake_at.isoformat(), **body})


# ─────────────────────────── C1 / H1 / H2 ───────────────────────────

def test_assess_matches_the_contract_example(client, auth):
    response = client.post(f"{API}/chronotype/assess", json={"mctq": CONTRACT_MCTQ}, headers=auth)
    assert response.status_code == 200, response.text
    body = response.json()
    assert (body["chronotype"], body["spectrum"], body["source"]) == ("bear", "intermediate", "mctq")
    assert body["mctq_result"] == {
        "sd_work_hours": 6.0, "sd_free_hours": 8.25, "sd_week_hours": 6.64, "msw": "03:30",
        "msf": "05:52", "msf_sc": "05:04", "oversleep_corrected": True, "social_jetlag_hours": 2.38,
        "chronotype": "bear"}
    assert body["phi_prior_hours"] == pytest.approx(18.39, abs=0.01)
    assert (body["natural_sleep_time"], body["natural_wake_time"]) == ("01:45", "08:24")
    assert body["sleep_shortfall_hours"] == pytest.approx(0.36, abs=0.01)
    week = body["typical_week"]
    assert len(week["days"]) == 7
    assert len(week["points"]) == 672
    assert week["days"][0]["wake_time"] == "06:30"


def test_assess_needs_rmeq_without_a_free_day(client, auth):
    seven = {**CONTRACT_MCTQ, "work_days": 7}
    response = client.post(f"{API}/chronotype/assess", json={"mctq": seven}, headers=auth)
    assert (response.status_code, response.json()["code"]) == (422, "RMEQ_REQUIRED")
    rmeq = client.post(f"{API}/chronotype/assess", json={"mctq": seven, "rmeq_score": 9}, headers=auth).json()
    assert (rmeq["source"], rmeq["chronotype"], rmeq["mctq_result"]) == ("rmeq", "wolf", None)
    assert client.post(f"{API}/chronotype/assess", json={}, headers=auth).status_code == 422


def test_what_if_earlier_bedtime(client, auth):
    wolf = {"sleep_onset_work": "01:30", "sleep_end_work": "06:30",
            "sleep_onset_free": "03:30", "sleep_end_free": "11:30", "work_days": 5}

    def thursday(shift):
        body = client.post(f"{API}/chronotype/assess", headers=auth,
                           json={"mctq": wolf, "school_onset_shift_minutes": shift}).json()
        return body["typical_week"]["days"][3]["minutes_past_threshold"]

    assert thursday(-30) < thursday(0)


def test_profile_lifecycle(client, auth):
    missing = client.get(f"{API}/health-profile", headers=auth)
    assert (missing.status_code, missing.json()["code"]) == (404, "HEALTH_PROFILE_NOT_FOUND")

    profile = put_profile(client, auth, chronotype="lion",
                          sleep_quality={"slow_onset_nights": "3+", "night_waking_nights": "0",
                                         "duration": ">3m"})
    assert profile["chronotype"] == "bear"  # computed from MCTQ, the sent value is ignored
    assert profile["chronotype_source"] == "mctq"
    assert profile["sleep_concern"] == "dolphin"
    assert profile["mctq_result"]["msf_sc"] == "05:04"
    assert profile["usual_wake_time"] == "06:30"
    assert client.get(f"{API}/health-profile", headers=auth).json() == profile
    assert client.get(f"{API}/users/me", headers=auth).json()["onboarding_completed"] is True

    self_report = put_profile(client, auth, mctq=None, chronotype="wolf")
    assert (self_report["chronotype"], self_report["chronotype_source"], self_report["spectrum"]) == (
        "wolf", "self_report", None)


# ─────────────────────────── H3–H6 ───────────────────────────

def test_sleep_log_crud_and_overlap(client, auth):
    night = today() - timedelta(days=1)
    created = add_log(client, auth, at(night, 23, 30), at(today(), 7), quality=4)
    assert created.status_code == 201, created.text
    log = created.json()
    assert (log["duration_minutes"], log["source"], log["confirmed"]) == (450, "manual", True)

    overlap = add_log(client, auth, at(today(), 6), at(today(), 8))
    assert (overlap.status_code, overlap.json()["code"]) == (409, "SLEEP_LOG_OVERLAP")
    assert add_log(client, auth, at(today(), 7), at(today(), 1)).status_code == 422
    assert add_log(client, auth, at(night, 6), at(today(), 7)).status_code == 422  # > 16 h

    url = f"{API}/sleep-logs/{log['id']}"
    updated = client.patch(url, json={"wake_at": at(today(), 7, 30).isoformat(), "note": "ngủ ngon"},
                           headers=auth).json()
    assert (updated["duration_minutes"], updated["note"]) == (480, "ngủ ngon")
    backwards = client.patch(url, json={"wake_at": at(night, 22).isoformat()}, headers=auth)
    assert (backwards.status_code, backwards.json()["code"]) == (400, "INVALID_RANGE")

    listed = client.get(f"{API}/sleep-logs", headers=auth).json()["items"]
    assert [item["id"] for item in listed] == [log["id"]]
    too_long = client.get(f"{API}/sleep-logs", params={"from": "2026-01-01", "to": "2026-12-31"}, headers=auth)
    assert too_long.json()["code"] == "RANGE_TOO_LARGE"

    assert client.delete(url, headers=auth).status_code == 204
    assert client.delete(url, headers=auth).json()["code"] == "SLEEP_LOG_NOT_FOUND"


# ─────────────────────────── H7 ───────────────────────────

def test_sleep_debt(client, auth):
    put_profile(client, auth)
    yesterday = today() - timedelta(days=1)
    add_log(client, auth, at(yesterday - timedelta(days=1), 23), at(yesterday, 5))   # 6 h
    add_log(client, auth, at(yesterday, 23), at(today(), 8))                          # 9 h
    body = client.get(f"{API}/sleep-debt", params={"days": 3}, headers=auth).json()
    assert [d["has_data"] for d in body["daily"]] == [False, True, True]
    assert [d["debt_minutes"] for d in body["daily"]] == [0, 120, -60]
    assert body["total_debt_minutes"] == 60
    assert body["average_sleep_minutes"] == 450
    assert body["daily"][2]["mid_sleep"] == "03:30"
    assert 0 <= body["current_process_s"] <= 1


def test_sleep_debt_needs_a_profile(client, auth):
    response = client.get(f"{API}/sleep-debt", headers=auth)
    assert (response.status_code, response.json()["code"]) == (404, "HEALTH_PROFILE_NOT_FOUND")


# ─────────────────────────── H8 ───────────────────────────

def test_biorhythm_typical_week(client, auth):
    put_profile(client, auth)
    tomorrow = today() + timedelta(days=1)
    client.post(f"{API}/timetable", headers=auth, json={"subjects": [{
        "name": "Giải tích", "day_of_week": tomorrow.isoweekday(), "start_time": "07:30",
        "end_time": "09:30", "start_date": (today() - timedelta(days=7)).isoformat(),
        "end_date": (today() + timedelta(days=30)).isoformat()}]})

    response = client.get(f"{API}/biorhythm", headers=auth)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["warnings"] == ["PRIOR_ONLY", "TYPICAL_WEEK"]
    assert body["model"]["personalization_level"] == "prior_only"
    assert len(body["points"]) == 96
    assert {p["sleep_state"] for p in body["points"]} == {"typical"}
    asleep = [p for p in body["points"] if p["asleep"]]
    assert asleep and all(p["kss_pred"] is None and p["alertness_score"] is None for p in asleep)
    awake = [p for p in body["points"] if not p["asleep"]]
    assert all(p["kss_lo"] <= p["kss_pred"] <= p["kss_hi"] for p in awake)
    assert body["peak_windows"] and body["low_windows"]
    assert max(w["mean_kss_pred"] for w in body["peak_windows"]) < min(w["mean_kss_pred"] for w in body["low_windows"])

    [night] = body["projected_sleep"]
    assert night["required_wake_at"] == at(tomorrow, 6, 30).isoformat()  # 07:30 class − 60 min prep
    # 8 h of sleep before the alarm at the latest.
    assert datetime.fromisoformat(night["recommended_sleep_at"]) <= at(tomorrow, 6, 30) - timedelta(hours=8)

    week = client.get(f"{API}/biorhythm", params={"days": 7, "interval_minutes": 60}, headers=auth).json()
    assert len(week["points"]) == 7 * 24
    assert client.get(f"{API}/biorhythm", params={"interval_minutes": 7}, headers=auth).status_code == 422


def test_biorhythm_with_sleep_logs(client, auth):
    put_profile(client, auth)
    add_log(client, auth, at(today() - timedelta(days=1), 23), at(today(), 6, 30))
    body = client.get(f"{API}/biorhythm", headers=auth).json()
    assert "TYPICAL_WEEK" not in body["warnings"]
    assert "NO_RECENT_SLEEP_DATA" in body["warnings"]
    states = {p["sleep_state"] for p in body["points"]}
    assert "projected" in states
