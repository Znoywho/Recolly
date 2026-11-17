"""The request transaction must be committed before the response leaves the server."""

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.deps import DbSession
from app.db.session import get_db


class RecordingSession:
    """Stands in for a SQLAlchemy session and records commit/rollback/close into a shared log."""

    def __init__(self, log: list[str]):
        self.log = log

    def commit(self):
        """Record a commit."""
        self.log.append("commit")

    def rollback(self):
        """Record a rollback."""
        self.log.append("rollback")

    def close(self):
        """Record a close."""
        self.log.append("close")


def build_app(log: list[str]) -> FastAPI:
    """Tiny app with one OK and one failing endpoint, logging when the response is ready."""
    app = FastAPI()

    def fake_db():
        """Yield a recording session, then close it like the real get_db."""
        session = RecordingSession(log)
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = fake_db

    @app.middleware("http")
    async def mark_response_ready(request, call_next):
        response = await call_next(request)
        log.append("response sent")
        return response

    @app.get("/ok")
    def ok(db: DbSession):
        return {}

    @app.get("/fail")
    def fail(db: DbSession):
        raise ValueError("boom")

    return app


def test_commit_happens_before_response_is_sent():
    log: list[str] = []
    TestClient(build_app(log)).get("/ok")
    assert log.index("commit") < log.index("response sent")
    assert "rollback" not in log


def test_failed_request_rolls_back_and_never_commits():
    log: list[str] = []
    TestClient(build_app(log), raise_server_exceptions=False).get("/fail")
    assert "rollback" in log
    assert "commit" not in log
