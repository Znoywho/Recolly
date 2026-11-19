"""GoogleClient retry on rate limits, against a fake HTTP transport (no network, no DB)."""

import httpx
import pytest

from app.service.google import client as google_client
from app.service.google.client import GoogleClient, GoogleError, GoogleUnavailable

RATE_LIMITED_403 = {"error": {"errors": [{"reason": "userRateLimitExceeded"}]}}


@pytest.fixture
def waits(monkeypatch):
    """Record backoff waits instead of sleeping."""
    slept: list[float] = []
    monkeypatch.setattr(google_client.time, "sleep", slept.append)
    return slept


def client_answering(*answers: tuple[int, dict]) -> tuple[GoogleClient, list]:
    """A GoogleClient whose HTTP calls get `answers` in order; also returns the request log."""
    requests: list[httpx.Request] = []
    queue = list(answers)

    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        status, body = queue.pop(0)
        return httpx.Response(status, json=body)

    return GoogleClient(httpx.Client(transport=httpx.MockTransport(handle))), requests


@pytest.mark.parametrize("limited", [(429, {}), (403, RATE_LIMITED_403)])
def test_rate_limit_is_retried_until_it_succeeds(waits, limited):
    """429 and 403 rateLimitExceeded are retried with growing waits."""
    google, requests = client_answering(limited, limited, (200, {"id": "e1"}))
    assert google.insert_event("token", "primary", {"summary": "x"}) == {"id": "e1"}
    assert len(requests) == 3
    assert waits == [1, 2]


def test_rate_limit_gives_up_after_the_last_wait(waits):
    """After every wait is used, the caller gets GoogleUnavailable (503 to the app)."""
    google, requests = client_answering(*[(429, {})] * 4)
    with pytest.raises(GoogleUnavailable):
        google.insert_event("token", "primary", {})
    assert len(requests) == 4
    assert waits == [1, 2, 4]


@pytest.mark.parametrize("status", [500, 400])
def test_other_errors_are_not_retried(waits, status):
    """A 5xx may already have run the insert, and a 4xx will not change: one request only."""
    google, requests = client_answering((status, {}))
    with pytest.raises(GoogleError):
        google.insert_event("token", "primary", {})
    assert len(requests) == 1
    assert waits == []
