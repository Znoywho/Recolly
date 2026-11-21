"""Request limits: 120/min on every route, 10/min and 2 parallel solves on POST /schedule/generate."""

from app.api import schedule_api
from app.core.redis_client import MemoryStore

GENERATE = "/api/v1/schedule/generate"
BODY = {"from": "2026-11-23", "to": "2026-11-29"}


def test_every_route_allows_120_per_minute_per_ip(client):
    codes = [client.get("/api/v1/health").status_code for _ in range(121)]
    assert codes[:120] == [200] * 120
    assert codes[120] == 429


def test_generate_allows_10_per_minute_then_429_with_retry_after(client, auth):
    for _ in range(10):  # no health profile yet: 404, but each call still counts
        assert client.post(GENERATE, json=BODY, headers=auth).status_code == 404
    response = client.post(GENERATE, json=BODY, headers=auth)
    assert response.status_code == 429
    assert response.json()["code"] == "RATE_LIMITED"
    assert 1 <= int(response.headers["Retry-After"]) <= 60
    assert client.get("/api/v1/todos", headers=auth).status_code == 200  # other routes still work


def test_generate_answers_503_when_all_solver_slots_are_busy(client, auth):
    for _ in range(schedule_api.MAX_PARALLEL_SOLVES):
        schedule_api._solver_slots.acquire()
    try:
        response = client.post(GENERATE, json=BODY, headers=auth)
    finally:
        for _ in range(schedule_api.MAX_PARALLEL_SOLVES):
            schedule_api._solver_slots.release()
    assert response.status_code == 503
    assert response.json()["code"] == "SCHEDULER_BUSY"
    assert response.headers["Retry-After"] == "5"
    assert client.post(GENERATE, json=BODY, headers=auth).status_code == 404  # slot freed: runs again


def test_memory_store_increment_with_ttl():
    store = MemoryStore()
    assert [store.increment_with_ttl("c", 60) for _ in range(3)] == [1, 2, 3]
    store.set_with_ttl("old", "7", 0)  # expired counter restarts
    assert store.increment_with_ttl("old", 60) == 1
