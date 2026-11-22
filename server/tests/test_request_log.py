"""log_request middleware: one line per request, level by status, health checks skipped."""

import logging

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)  # not a context manager: no lifespan, so no database needed


def request_lines(caplog):
    """Records written by the request logger."""
    return [r for r in caplog.records if r.name == "app.request"]


def test_success_is_logged_at_info_with_duration_and_caller(caplog):
    caplog.set_level(logging.INFO)
    client.get("/")
    [line] = request_lines(caplog)
    assert line.levelno == logging.INFO
    assert line.getMessage().startswith("GET / 200 ")
    assert "ms ip:" in line.getMessage()


def test_client_error_is_logged_at_warning(caplog):
    caplog.set_level(logging.INFO)
    client.get("/no-such-route")
    [line] = request_lines(caplog)
    assert line.levelno == logging.WARNING
    assert "GET /no-such-route 404 " in line.getMessage()


def test_bad_token_is_counted_by_ip(caplog):
    caplog.set_level(logging.INFO)
    client.get("/", headers={"Authorization": "Bearer not-a-jwt"})
    [line] = request_lines(caplog)
    assert line.getMessage().endswith("ip:testclient")
