"""Push notifications through FCM HTTP v1 (the legacy server-key API is shut down).

Docs: https://firebase.google.com/docs/cloud-messaging/send/v1-api (Firebase, official).
Auth uses a Firebase service account JSON (FCM_SERVICE_ACCOUNT_FILE); without it, LogSender
only logs, so the reminder job still runs in dev and tests.
"""

import json
import logging
import time
from functools import cache
from typing import Any

import httpx
import jwt

from app.config import Config

logger = logging.getLogger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
JWT_BEARER = "urn:ietf:params:oauth:grant-type:jwt-bearer"


class FcmSender:
    """Sends one PushPayload to one device token with a service account."""

    def __init__(self, service_account: dict[str, Any], http: httpx.Client | None = None):
        self.account = service_account
        self.http = http or httpx.Client(timeout=15)
        self._token: tuple[str, float] | None = None  # (access token, expiry as time.monotonic())

    def _access_token(self) -> str:
        """OAuth token from a signed JWT assertion (RFC 7523), cached until 1 min before expiry."""
        if self._token and self._token[1] > time.monotonic():
            return self._token[0]
        now = int(time.time())
        assertion = jwt.encode({"iss": self.account["client_email"], "scope": FCM_SCOPE,
                                "aud": self.account["token_uri"], "iat": now, "exp": now + 3600},
                               self.account["private_key"], algorithm="RS256")
        response = self.http.post(self.account["token_uri"],
                                  data={"grant_type": JWT_BEARER, "assertion": assertion})
        response.raise_for_status()
        data = response.json()
        self._token = (data["access_token"], time.monotonic() + int(data.get("expires_in", 3600)) - 60)
        return self._token[0]

    def send(self, fcm_token: str, payload: dict[str, Any]) -> bool:
        """Send; False means the token is dead (app uninstalled) and the device should be removed."""
        url = f"https://fcm.googleapis.com/v1/projects/{self.account['project_id']}/messages:send"
        message = {"token": fcm_token,
                   "notification": {"title": payload["title"], "body": payload["body"]},
                   "data": {k: str(v) for k, v in payload.items()}}  # FCM data values must be strings
        response = self.http.post(url, json={"message": message},
                                  headers={"Authorization": f"Bearer {self._access_token()}"})
        if response.status_code == 404 or is_invalid_token_error(response):  # UNREGISTERED / malformed token
            return False
        response.raise_for_status()
        return True


def is_invalid_token_error(response: httpx.Response) -> bool:
    """True for 400 INVALID_ARGUMENT blaming `message.token`; a bad payload also gives 400 and must not drop devices."""
    if response.status_code != 400:
        return False
    try:
        details = response.json()["error"].get("details", [])
    except (ValueError, KeyError, TypeError):
        return False
    return any(violation.get("field") == "message.token"
               for detail in details for violation in detail.get("fieldViolations", []))


class LogSender:
    """Stand-in when FCM is not configured: logs what would be sent."""

    def send(self, fcm_token: str, payload: dict[str, Any]) -> bool:
        """Log the payload; the token is always kept."""
        logger.info("push (FCM not configured) to %s…: %s", fcm_token[:8], payload)
        return True


@cache
def get_push_sender() -> FcmSender | LogSender:
    """FcmSender when FCM_SERVICE_ACCOUNT_FILE is set, else LogSender."""
    if not Config.FCM_SERVICE_ACCOUNT_FILE:
        return LogSender()
    with open(Config.FCM_SERVICE_ACCOUNT_FILE) as file:
        return FcmSender(json.load(file))
