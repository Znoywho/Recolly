"""Smoke-test the real Google sign-in + Calendar push against a running server.

Uses about 6 Google API requests per run (token exchange, calendar check, insert, delete),
so run it by hand when needed; `pytest` keeps using tests/fake_google.py and costs no quota.

One-time setup:
    1. In the Web OAuth client, add the redirect URI  http://localhost:8765
    2. Start the server with that redirect URI (codes are bound to it):
           GOOGLE_REDIRECT_URI=http://localhost:8765 uvicorn app.main:app --reload

Usage (from server/):
    python scripts/google_smoke.py                 # sign in, push one event, then delete it
    python scripts/google_smoke.py --keep          # leave the event in Google Calendar to look at
"""

import os
import socket
import sys
import webbrowser
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlencode, urlparse

import httpx

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.config import Config  # noqa: E402

API = os.getenv("SMOKE_API_URL", "http://localhost:8000/api/v1")
REDIRECT_PORT = 8765
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


def run_smoke_test(keep_event: bool) -> None:
    """Sign in, confirm Calendar is linked, push one event to Google, then clean it up."""
    try:  # fail before the browser step, so no Google sign-in is wasted
        httpx.get(f"{API}/health", timeout=5)
    except httpx.ConnectError:
        sys.exit(f"Server is not running at {API}. Start it with:\n"
                 "    GOOGLE_REDIRECT_URI=http://localhost:8765 venv/bin/uvicorn app.main:app --port 8000")
    code = get_auth_code()
    with httpx.Client(base_url=API, timeout=30) as http:
        auth = check(http.post("/auth/google", json={"server_auth_code": code}), "sign in")
        http.headers["Authorization"] = f"Bearer {auth['access_token']}"
        print(f"    user: {auth['user'].get('email')}  new: {auth['is_new_user']}")

        status = check(http.get("/calendar/status"), "calendar status")
        print(f"    {status}")

        start = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(days=1)
        event = check(http.post("/events", json={
            "title": "[smoke] Recolly test",
            "start_at": start.isoformat(),
            "end_at": (start + timedelta(minutes=30)).isoformat(),
        }), "create event")
        print(f"    {check(http.post('/calendar/sync'), 'push to Google')}")

        if keep_event:
            print("Event kept: look for '[smoke] Recolly test' tomorrow in Google Calendar.")
            return
        check(http.delete(f"/events/{event['id']}"), "delete event")
        print(f"    {check(http.post('/calendar/sync'), 'push deletion to Google')}")


if __name__ == "__main__":
    run_smoke_test(keep_event="--keep" in sys.argv)
