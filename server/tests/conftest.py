"""Shared fixtures.

API tests need a real PostgreSQL (the models use JSONB and ARRAY). Point TEST_DATABASE_URL
at an empty database; it is wiped on every run. Without it those tests are skipped:

    TEST_DATABASE_URL=postgresql+psycopg2://postgres:<password>@localhost:5433/recolly_test pytest
"""

import os
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from cryptography.fernet import Fernet

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")

# app.config reads the environment at import time, so set it before importing the app.
os.environ["POSTGRES_DATABASE_URL"] = TEST_DATABASE_URL or "postgresql+psycopg2://unused@localhost:1/unused"
os.environ["JWT_SECRET"] = "test-jwt-secret-that-is-at-least-32-bytes"
os.environ["TOKEN_ENCRYPTION_KEY"] = Fernet.generate_key().decode()
os.environ["GOOGLE_CLIENT_ID"] = "test-client-id"
os.environ["GOOGLE_CLIENT_SECRET"] = "test-client-secret"
os.environ["WEBHOOK_BASE_URL"] = ""
os.environ["REDIS_URL"] = ""

from tests.fake_google import FakeGoogle  # noqa: E402

TZ_NAME = "Asia/Ho_Chi_Minh"


@pytest.fixture(scope="session")
def database():
    if not TEST_DATABASE_URL:
        pytest.skip("TEST_DATABASE_URL is not set")
    import app.models  # noqa: F401
    from app.db.base import Base
    from app.db.session import engine

    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield engine
    engine.dispose()


@pytest.fixture
def google():
    return FakeGoogle()


@pytest.fixture
def client(database, google):
    from fastapi.testclient import TestClient
    from sqlalchemy import text

    from app.db.base import Base
    from app.main import app
    from app.service.google import get_google_client

    app.dependency_overrides[get_google_client] = lambda: google
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    tables = ", ".join(table.name for table in Base.metadata.sorted_tables)
    with database.begin() as conn:
        conn.execute(text(f"TRUNCATE {tables} CASCADE"))


@pytest.fixture
def db(database):
    from app.db.session import SessionLocal

    with SessionLocal() as session:
        yield session


def make_user(db, email: str = "sv@example.com", timezone: str = TZ_NAME):
    from app.models.user import User

    user = User(google_sub=f"sub-{uuid.uuid4().hex}", email=email, display_name="Sinh Viên",
                timezone=timezone)
    db.add(user)
    db.commit()
    return user


def bearer(user_id: uuid.UUID) -> dict[str, str]:
    from app.core.security import create_access_token

    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


@pytest.fixture
def user(client, db):
    return make_user(db)


@pytest.fixture
def auth(user):
    return bearer(user.id)


@pytest.fixture
def connected(client, auth, google):
    """The user from `auth` with Google Calendar connected through G6."""
    google.add_grant("calendar-code", sub="google-sub-1", email="sv@gmail.com", calendar=True)
    response = client.post("/api/v1/calendar/connection", json={"server_auth_code": "calendar-code"},
                           headers=auth)
    assert response.status_code == 200, response.text
    return auth


def iso(dt: datetime) -> str:
    return dt.isoformat()


def utc(*args) -> datetime:
    return datetime(*args, tzinfo=UTC)


def days_from_now(days: int) -> datetime:
    return datetime.now(UTC) + timedelta(days=days)
