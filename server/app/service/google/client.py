"""Small REST client for Google OAuth and Calendar v3 (httpx, no discovery client).

Routers get it through `GoogleDep`; tests override `get_google_client` with a fake.
"""

import time
from dataclasses import dataclass
from datetime import UTC, datetime
from functools import cache
from typing import Annotated, Any
from urllib.parse import quote

import httpx
import jwt
from fastapi import Depends

from app.config import Config
from app.core.security import hash_token

TOKEN_URL = "https://oauth2.googleapis.com/token"
REVOKE_URL = "https://oauth2.googleapis.com/revoke"
CALENDAR_API = "https://www.googleapis.com/calendar/v3"
CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.events"
GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}
CHANNEL_TTL_SECONDS = 7 * 24 * 3600


class GoogleError(Exception):
    """A Google API call failed. `status` is the HTTP status (0 = network error)."""

    def __init__(self, status: int, reason: str = ""):
        super().__init__(f"Google API error {status}: {reason}")
        self.status = status
        self.reason = reason


class GoogleAuthRevoked(GoogleError):
    """The refresh token is expired or revoked; the user must connect again."""


class GoogleUnavailable(GoogleError):
    """Network error, 5xx, rate limit, or Google OAuth not configured on the server."""


@dataclass(frozen=True)
class GoogleGrant:
    sub: str
    email: str
    name: str | None
    picture: str | None
    refresh_token: str | None
    scopes: frozenset[str]


@dataclass(frozen=True)
class EventPage:
    items: list[dict[str, Any]]
    next_page_token: str | None
    next_sync_token: str | None


def _reason(response: httpx.Response) -> str:
    try:
        body = response.json()
    except ValueError:
        return response.text[:200]
    error = body.get("error")
    if isinstance(error, str):  # OAuth endpoints
        return error
    if isinstance(error, dict):  # Calendar API
        errors = error.get("errors") or [{}]
        return errors[0].get("reason") or error.get("status") or str(error.get("message", ""))
    return ""


class GoogleClient:
    def __init__(self, http: httpx.Client | None = None):
        self.http = http or httpx.Client(timeout=15)
        # hash(refresh token) -> (access token, expiry as time.monotonic())
        self._access: dict[str, tuple[str, float]] = {}

    # ─────────────────────────── OAuth ───────────────────────────

    def _post_token(self, data: dict[str, str]) -> dict[str, Any]:
        if not (Config.GOOGLE_CLIENT_ID and Config.GOOGLE_CLIENT_SECRET):
            raise GoogleUnavailable(0, "Google OAuth is not configured on the server")
        data = {**data, "client_id": Config.GOOGLE_CLIENT_ID,
                "client_secret": Config.GOOGLE_CLIENT_SECRET}
        try:
            response = self.http.post(TOKEN_URL, data=data)
        except httpx.HTTPError as exc:
            raise GoogleUnavailable(0, str(exc)) from exc
        if response.status_code >= 500:
            raise GoogleUnavailable(response.status_code, _reason(response))
        if response.status_code >= 400:
            reason = _reason(response)
            if reason == "invalid_grant" and data["grant_type"] == "refresh_token":
                raise GoogleAuthRevoked(response.status_code, reason)
            raise GoogleError(response.status_code, reason)
        return response.json()

    def _remember(self, refresh_token: str, access_token: str, expires_in: int) -> None:
        self._access[hash_token(refresh_token)] = (access_token, time.monotonic() + expires_in - 60)

    def exchange_code(self, code: str) -> GoogleGrant:
        """Exchange the one-time `serverAuthCode` from google_sign_in."""
        data = self._post_token({"code": code, "grant_type": "authorization_code",
                                 "redirect_uri": Config.GOOGLE_REDIRECT_URI})
        if "id_token" not in data:
            raise GoogleError(400, "missing id_token (request the openid scope)")
        # Received straight from Google's token endpoint over TLS, so the signature check
        # can be skipped (OpenID Connect Core 3.1.3.7); audience and issuer are still checked.
        claims = jwt.decode(data["id_token"], options={"verify_signature": False})
        if claims.get("aud") != Config.GOOGLE_CLIENT_ID or claims.get("iss") not in GOOGLE_ISSUERS:
            raise GoogleError(400, "id_token was issued for another client")
        refresh_token = data.get("refresh_token")
        if refresh_token:
            self._remember(refresh_token, data["access_token"], int(data.get("expires_in", 3600)))
        return GoogleGrant(
            sub=claims["sub"],
            email=claims.get("email", ""),
            name=claims.get("name"),
            picture=claims.get("picture"),
            refresh_token=refresh_token,
            scopes=frozenset(data.get("scope", "").split()),
        )

    def access_token(self, refresh_token: str) -> str:
        key = hash_token(refresh_token)
        cached = self._access.get(key)
        if cached and cached[1] > time.monotonic():
            return cached[0]
        data = self._post_token({"refresh_token": refresh_token, "grant_type": "refresh_token"})
        self._remember(refresh_token, data["access_token"], int(data.get("expires_in", 3600)))
        return data["access_token"]

    def revoke(self, token: str) -> None:
        """Best effort: an already revoked token is not an error."""
        self._access.pop(hash_token(token), None)
        try:
            self.http.post(REVOKE_URL, data={"token": token})
        except httpx.HTTPError:
            pass

    # ────────────────────────── Calendar ──────────────────────────

    def _call(self, method: str, path: str, access_token: str, *,
              params: dict[str, Any] | None = None, json: dict[str, Any] | None = None,
              headers: dict[str, str] | None = None) -> dict[str, Any] | None:
        try:
            response = self.http.request(
                method, f"{CALENDAR_API}{path}", params=params, json=json,
                headers={"Authorization": f"Bearer {access_token}", **(headers or {})},
            )
        except httpx.HTTPError as exc:
            raise GoogleUnavailable(0, str(exc)) from exc
        status = response.status_code
        if status < 300:
            return response.json() if response.content else None
        reason = _reason(response)
        if status == 401:
            raise GoogleAuthRevoked(status, reason)
        if status == 429 or status >= 500 or reason in ("rateLimitExceeded", "userRateLimitExceeded"):
            raise GoogleUnavailable(status, reason)
        raise GoogleError(status, reason)

    @staticmethod
    def _events_path(calendar_id: str, event_id: str | None = None) -> str:
        path = f"/calendars/{quote(calendar_id, safe='')}/events"
        return f"{path}/{quote(event_id, safe='')}" if event_id else path

    def get_event(self, access_token: str, calendar_id: str, event_id: str) -> dict[str, Any] | None:
        try:
            return self._call("GET", self._events_path(calendar_id, event_id), access_token)
        except GoogleError as exc:
            if exc.status in (404, 410):
                return None
            raise

    def insert_event(self, access_token: str, calendar_id: str, body: dict[str, Any]) -> dict[str, Any]:
        return self._call("POST", self._events_path(calendar_id), access_token, json=body)

    def patch_event(self, access_token: str, calendar_id: str, event_id: str, body: dict[str, Any],
                    etag: str | None = None) -> dict[str, Any]:
        """With `etag`, Google answers 412 if the event changed since (two-way conflict check)."""
        headers = {"If-Match": etag} if etag else None
        return self._call("PATCH", self._events_path(calendar_id, event_id), access_token,
                          json=body, headers=headers)

    def delete_event(self, access_token: str, calendar_id: str, event_id: str) -> None:
        try:
            self._call("DELETE", self._events_path(calendar_id, event_id), access_token)
        except GoogleError as exc:
            if exc.status not in (404, 410):  # already gone
                raise

    def list_events(self, access_token: str, calendar_id: str, *, sync_token: str | None = None,
                    time_min: datetime | None = None, page_token: str | None = None) -> EventPage:
        """One page of events.list. A sync token cannot be combined with time filters."""
        params: dict[str, Any] = {"maxResults": 2500, "singleEvents": "false"}
        if sync_token:
            params["syncToken"] = sync_token
        elif time_min:
            params["timeMin"] = time_min.astimezone(UTC).isoformat()
        if page_token:
            params["pageToken"] = page_token
        data = self._call("GET", self._events_path(calendar_id), access_token, params=params) or {}
        return EventPage(items=data.get("items", []), next_page_token=data.get("nextPageToken"),
                         next_sync_token=data.get("nextSyncToken"))

    def can_write(self, access_token: str, calendar_id: str) -> bool:
        """True if the calendar exists and accepts event reads with the granted scope."""
        try:
            self._call("GET", self._events_path(calendar_id), access_token, params={"maxResults": 1})
        except GoogleError as exc:
            if exc.status in (400, 403, 404):
                return False
            raise
        return True

    def watch(self, access_token: str, calendar_id: str, channel_id: str, token: str,
              address: str) -> tuple[str, datetime]:
        """Start push notifications; returns (resource id, expiry)."""
        body = {"id": channel_id, "type": "web_hook", "address": address, "token": token,
                "params": {"ttl": str(CHANNEL_TTL_SECONDS)}}
        data = self._call("POST", f"{self._events_path(calendar_id)}/watch", access_token, json=body) or {}
        expires = datetime.fromtimestamp(int(data.get("expiration", 0)) / 1000, UTC)
        return data["resourceId"], expires

    def stop_channel(self, access_token: str, channel_id: str, resource_id: str) -> None:
        try:
            self._call("POST", "/channels/stop", access_token,
                       json={"id": channel_id, "resourceId": resource_id})
        except GoogleError as exc:
            if exc.status != 404:
                raise


@cache
def get_google_client() -> GoogleClient:
    return GoogleClient()


GoogleDep = Annotated[GoogleClient, Depends(get_google_client)]
