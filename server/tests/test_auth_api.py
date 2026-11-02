from datetime import UTC, datetime, timedelta

import jwt
import pytest

from app.config import Config

API = "/api/v1"


def sign_in(client, google, code="code-1", calendar=False):
    google.add_grant(code, sub="google-sub-1", email="sv@gmail.com", calendar=calendar)
    return client.post(f"{API}/auth/google", json={"server_auth_code": code})


def test_sign_in_creates_the_user_once(client, google):
    first = sign_in(client, google)
    assert first.status_code == 200, first.text
    body = first.json()
    assert body["is_new_user"] is True
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 900
    user = body["user"]
    assert user["email"] == "sv@gmail.com"
    assert user["timezone"] == "Asia/Ho_Chi_Minh"
    assert user["onboarding_completed"] is False
    assert user["google_calendar_connected"] is False
    assert user["created_at"].endswith("+07:00")

    again = sign_in(client, google, code="code-2").json()
    assert again["is_new_user"] is False
    assert again["user"]["id"] == user["id"]


def test_sign_in_with_calendar_scope_connects_calendar(client, google):
    body = sign_in(client, google, calendar=True).json()
    assert body["user"]["google_calendar_connected"] is True
    status = client.get(f"{API}/calendar/status",
                        headers={"Authorization": f"Bearer {body['access_token']}"}).json()
    assert status["connected"] is True
    assert status["google_email"] == "sv@gmail.com"
    assert status["calendar_id"] == "primary"


def test_sign_in_still_works_without_an_encryption_key(client, google, monkeypatch):
    monkeypatch.setattr(Config, "TOKEN_ENCRYPTION_KEY", "")
    response = sign_in(client, google, calendar=True)
    assert response.status_code == 200
    assert response.json()["user"]["google_calendar_connected"] is False


def test_rejected_code(client):
    response = client.post(f"{API}/auth/google", json={"server_auth_code": "unknown"})
    assert response.status_code == 400
    assert response.json()["code"] == "GOOGLE_CODE_INVALID"


def test_google_down(client, google):
    google.down = True
    response = sign_in(client, google)
    assert response.status_code == 503
    assert response.json()["code"] == "GOOGLE_UNAVAILABLE"


def test_refresh_rotates_and_reuse_ends_all_sessions(client, google):
    tokens = sign_in(client, google).json()
    rotated = client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert rotated.status_code == 200
    new = rotated.json()
    assert new["refresh_token"] != tokens["refresh_token"]

    reused = client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert reused.status_code == 401
    assert reused.json()["code"] == "REFRESH_TOKEN_INVALID"
    # Reuse of a rotated token may mean it leaked: the newer one is revoked too.
    assert client.post(f"{API}/auth/refresh", json={"refresh_token": new["refresh_token"]}).status_code == 401


def test_logout_revokes_the_refresh_token(client, google):
    tokens = sign_in(client, google).json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    response = client.post(f"{API}/auth/logout", json={"refresh_token": tokens["refresh_token"]},
                           headers=headers)
    assert response.status_code == 204
    assert client.post(f"{API}/auth/refresh",
                       json={"refresh_token": tokens["refresh_token"]}).status_code == 401


@pytest.mark.parametrize("header", [None, "Bearer garbage", "Basic abc"])
def test_invalid_access_token(client, user, header):
    headers = {"Authorization": header} if header else {}
    response = client.get(f"{API}/users/me", headers=headers)
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_INVALID"
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_expired_access_token(client, user):
    expired = jwt.encode({"sub": str(user.id), "type": "access",
                          "exp": datetime.now(UTC) - timedelta(minutes=1)},
                         Config.JWT_SECRET, algorithm="HS256")
    response = client.get(f"{API}/users/me", headers={"Authorization": f"Bearer {expired}"})
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_EXPIRED"
