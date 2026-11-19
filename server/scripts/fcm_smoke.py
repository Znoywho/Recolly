"""Smoke-test real FCM push (R39) with the Firebase service account; no server or DB needed.

One-time setup:
    1. Firebase console → Project settings → Service accounts → Generate new private key.
    2. Save the JSON outside the repo and set FCM_SERVICE_ACCOUNT_FILE=/path/to/key.json in server/.env.

Usage (from server/):
    python scripts/fcm_smoke.py --check          # credentials + project only (validate_only, nothing delivered)
    python scripts/fcm_smoke.py <fcm_token>      # deliver one sample deadline reminder to that phone
The FCM token comes from the Flutter app (firebase_messaging getToken(), also sent to POST /devices).
"""

import argparse
import json
import os
import sys

import httpx

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.config import Config  # noqa: E402
from app.service.push import FcmSender  # noqa: E402

# A well-formed but unknown token: with validate_only, FCM checks auth first, then rejects the token.
PLACEHOLDER_TOKEN = "fcm-smoke-check"
SAMPLE_PAYLOAD = {"type": "deadline", "title": "[smoke] Còn 2 giờ: Nộp báo cáo",
                  "body": "Nếu bạn thấy thông báo này, FCM đã chạy.", "deep_link": "recolly://todos/smoke",
                  "scheduled_for": "2026-11-20T17:00:00+07:00"}


def load_sender() -> FcmSender:
    """FcmSender from FCM_SERVICE_ACCOUNT_FILE, or exit with a hint."""
    if not Config.FCM_SERVICE_ACCOUNT_FILE:
        sys.exit("FCM_SERVICE_ACCOUNT_FILE is not set (see the setup at the top of this file).")
    with open(Config.FCM_SERVICE_ACCOUNT_FILE) as file:
        return FcmSender(json.load(file))


def check_credentials(sender: FcmSender) -> None:
    """Get an OAuth token, then validate (not send) a message: 401/403 = bad key or project."""
    print("1/2 OAuth token from the service account ...", end=" ")
    token = sender._access_token()
    print("ok")
    print(f"2/2 validate_only message to project {sender.account['project_id']} ...", end=" ")
    url = f"https://fcm.googleapis.com/v1/projects/{sender.account['project_id']}/messages:send"
    response = sender.http.post(url, headers={"Authorization": f"Bearer {token}"}, json={
        "validate_only": True, "message": {"token": PLACEHOLDER_TOKEN, "notification": {"title": "check"}}})
    if response.status_code in (401, 403):
        sys.exit(f"FAILED {response.status_code}: the key cannot send for this project.\n{response.text}")
    if response.status_code == 404 and "UNREGISTERED" not in response.text:
        sys.exit(f"FAILED 404: unknown project_id or FCM API not enabled.\n{response.text}")
    # 200, or 400/404 about the placeholder token: auth and project are fine.
    print(f"ok (HTTP {response.status_code}, the placeholder token is expected to be rejected)")
    print("Credentials and project work. Next: python scripts/fcm_smoke.py <fcm_token from the app>")


def send_sample(sender: FcmSender, fcm_token: str) -> None:
    """Deliver SAMPLE_PAYLOAD to one phone."""
    print(f"Sending a sample reminder to {fcm_token[:12]}... ", end=" ")
    try:
        delivered = sender.send(fcm_token, SAMPLE_PAYLOAD)
    except httpx.HTTPStatusError as exc:
        sys.exit(f"FAILED {exc.response.status_code}: {exc.response.text}")
    if not delivered:
        sys.exit("FAILED: token is UNREGISTERED (app uninstalled or token rotated); get a fresh one.")
    print("sent. Check the phone's notification shade.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("fcm_token", nargs="?", help="token of a real phone; omit with --check")
    parser.add_argument("--check", action="store_true", help="validate credentials only, deliver nothing")
    args = parser.parse_args()
    if not args.check and not args.fcm_token:
        parser.error("give an fcm_token, or --check")
    fcm = load_sender()
    if args.check:
        check_credentials(fcm)
    else:
        send_sample(fcm, args.fcm_token)
