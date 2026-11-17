"""Smoke-test the real Google sign-in + Calendar push against a running server.

Uses about 5 Google API requests per basic run (about 10 with every flag),
so run it by hand when needed; `pytest` keeps using tests/fake_google.py and costs no quota.

One-time setup:
    1. In the Web OAuth client, add the redirect URI  http://localhost:8765
    2. Start the server with that redirect URI (codes are bound to it):
           GOOGLE_REDIRECT_URI=http://localhost:8765 uvicorn app.main:app --reload

Usage (from server/):
    python scripts/google_smoke.py                 # sign in, push, rename, delete one event
    python scripts/google_smoke.py --keep          # leave the event in Google Calendar to look at
    python scripts/google_smoke.py --two-way       # also rename it on Google, then pull that change
    python scripts/google_smoke.py --disconnect    # finally disconnect and revoke the Google token
Flags combine, e.g. --two-way --disconnect.
"""

import os
import socket
import sys
import time
import uuid
import webbrowser
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlencode, urlparse

import httpx

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.config import Config  # noqa: E402
from app.core.security import decrypt  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.models.event import Event  # noqa: E402
from app.service.google import GoogleClient  # noqa: E402

API = os.getenv("SMOKE_API_URL", "http://localhost:8000/api/v1")
REDIRECT_PORT = 8765
PULL_COOLDOWN_SECONDS = 125  # app.service.calendar_sync.PULL_COOLDOWN plus a small margin
REDIRECT_URI = f"http://localhost:{REDIRECT_PORT}"
SCOPES = "openid email profile https://www.googleapis.com/auth/calendar.events"


class DualStackServer(HTTPServer):
    """HTTP server on both ::1 and 127.0.0.1, since browsers may resolve localhost to either."""

    address_family = socket.AF_INET6
    timeout = 300  # handle_request() gives up after 5 minutes instead of hanging

    def server_bind(self):
        """Accept IPv4 connections on the IPv6 socket too, then bind as usual."""
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


class CodeCatcher(BaseHTTPRequestHandler):
    """Receives Google's redirect on localhost and keeps the `code` query parameter."""

    code: str | None = None
    error: str | None = None

    def do_GET(self):
        """Store the code (or error) from the redirect and tell the user to close the tab."""
        query = parse_qs(urlparse(self.path).query)
        CodeCatcher.code = query.get("code", [None])[0]
        CodeCatcher.error = query.get("error", [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write("Done, you can close this tab.".encode())

    def log_message(self, *args):
        """Silence the default per-request log line."""


def get_auth_code() -> str:
    """Open Google's consent page and wait for the one-time auth code on localhost."""
    if not Config.GOOGLE_CLIENT_ID:
        sys.exit("GOOGLE_CLIENT_ID is empty: fill server/.env first")
    params = {
        "client_id": Config.GOOGLE_CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "response_type": "code",
        "scope": SCOPES,
        "access_type": "offline",  # ask for a refresh token, like forceCodeForRefreshToken on Android
        "prompt": "consent",       # Google only resends a refresh token after a fresh consent
    }
    url = "https://accounts.google.com/o/oauth2/v2/auth?" + urlencode(params)
    print("Opening the browser for Google sign-in…\nIf it does not open, visit:\n" + url)
    webbrowser.open(url)
    with DualStackServer(("::", REDIRECT_PORT), CodeCatcher) as server:
        server.handle_request()
    if not CodeCatcher.code:
        sys.exit(f"No code received (Google error: {CodeCatcher.error}). "
                 "If the browser showed an error page, read it: redirect_uri_mismatch / access_denied?")
    return CodeCatcher.code


def check(response: httpx.Response, step: str) -> dict:
    """Print one step's result and stop the script if the server returned an error."""
    print(f"[{response.status_code}] {step}")
    if response.status_code >= 400:
        sys.exit(response.text)
    return response.json() if response.content else {}


failures: list[str] = []


def expect(condition: bool, description: str) -> None:
    """Print a pass/fail line for one expectation and remember failures for the exit code."""
    print(f"    {'OK  ' if condition else 'FAIL'} {description}")
    if not condition:
        failures.append(description)


def rename_on_google(event_id: str, title: str) -> None:
    """Play the user editing the event in Google Calendar: patch it with the server's stored token."""
    google = GoogleClient()
    with SessionLocal() as db:
        event = db.get(Event, uuid.UUID(event_id))
        conn = event.user.calendar_connection
        token = google.access_token(decrypt(conn.refresh_token_encrypted))
        google.patch_event(token, conn.calendar_id, event.google_event_id, {"summary": title})


def sync(http: httpx.Client, step: str) -> dict:
    """Call POST /calendar/sync and print its counters."""
    result = check(http.post("/calendar/sync"), step)
    print(f"    {result}")
    return result


def run_smoke_test(keep_event: bool, two_way: bool, disconnect: bool) -> None:
    """Exercise every Google feature the server uses, in the order a real user would."""
    try:  # fail before the browser step, so no Google sign-in is wasted
        httpx.get(f"{API}/health", timeout=5)
    except httpx.ConnectError:
        sys.exit(f"Server is not running at {API}. Start it with:\n"
                 "    GOOGLE_REDIRECT_URI=http://localhost:8765 venv/bin/uvicorn app.main:app --port 8000")
    code = get_auth_code()
    with httpx.Client(base_url=API, timeout=30) as http:
        # 1. OAuth: code exchange + id_token (Google token endpoint)
        auth = check(http.post("/auth/google", json={"server_auth_code": code}), "sign in")
        http.headers["Authorization"] = f"Bearer {auth['access_token']}"
        print(f"    user: {auth['user'].get('email')}  new: {auth['is_new_user']}")

        status = check(http.get("/calendar/status"), "calendar status")
        expect(status["connected"], "Calendar linked at sign-in (refresh token stored)")

        # 2. Calendar push: insert (events.insert)
        start = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(days=1)
        event = check(http.post("/events", json={
            "title": "[smoke] Recolly test",
            "start_at": start.isoformat(),
            "end_at": (start + timedelta(minutes=30)).isoformat(),
        }), "create event")
        expect(sync(http, "push new event")["pushed"] == 1, "event inserted into Google Calendar")

        # 3. Calendar push: update (events.patch)
        check(http.patch(f"/events/{event['id']}", json={"title": "[smoke] Recolly test (edited)"}),
              "rename event")
        expect(sync(http, "push rename")["pushed"] == 1, "rename patched in Google Calendar")

        # 4. Two-way: pull Google's changes (events.list with syncToken)
        if two_way:
            check(http.patch("/calendar/settings", json={"two_way_sync": True}), "turn on two-way sync")
            sync(http, "first pull (full sync of the last days)")
            first_pull_at = time.monotonic()
            rename_on_google(event["id"], "[smoke] changed on Google")
            print("[ok ] renamed the event directly in Google Calendar (as if the user did)")
            # The server skips pulls for PULL_COOLDOWN (2 min) after the last one.
            wait = PULL_COOLDOWN_SECONDS - (time.monotonic() - first_pull_at)
            if wait > 0:
                print(f"    waiting {wait:.0f}s for the server's pull cooldown…")
                time.sleep(wait)
            expect(sync(http, "pull Google's change")["pulled"] >= 1, "change pulled from Google")
            title = check(http.get(f"/events/{event['id']}"), "read event")["title"]
            expect(title == "[smoke] changed on Google", f"local title updated (now: {title!r})")

        # 5. Calendar push: delete (events.delete)
        if keep_event:
            print("Event kept: look for it tomorrow in Google Calendar.")
        else:
            check(http.delete(f"/events/{event['id']}"), "delete event")
            expect(sync(http, "push deletion")["pushed"] == 1, "event deleted from Google Calendar")

        # 6. Disconnect: token revoke (oauth2 revoke endpoint)
        if disconnect:
            check(http.delete("/calendar/connection"), "disconnect Calendar")
            expect(not check(http.get("/calendar/status"), "calendar status")["connected"],
                   "connection removed and Google token revoked")

    print(f"\n{'All checks passed' if not failures else f'{len(failures)} check(s) failed: {failures}'}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    run_smoke_test(keep_event="--keep" in sys.argv, two_way="--two-way" in sys.argv,
                   disconnect="--disconnect" in sys.argv)
