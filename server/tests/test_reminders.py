"""R39 reminder rules + job, with a fake push sender; FcmSender against a fake HTTP transport."""

import json
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.jobs.send_reminders import run_send_reminders
from app.service.push import FcmSender
from app.service.reminders import due_reminders

API = "/api/v1"
TZ = ZoneInfo("Asia/Ho_Chi_Minh")
PAYLOAD_KEYS = {"type", "title", "body", "deep_link", "scheduled_for"}  # contract PushPayload


class FakeSender:
    """Records every push; tokens starting with 'dead' are reported as unregistered."""

    def __init__(self):
        self.sent: list[tuple[str, dict]] = []

    def send(self, fcm_token: str, payload: dict) -> bool:
        """Record and answer like FcmSender.send."""
        if fcm_token.startswith("dead"):
            return False
        self.sent.append((fcm_token, payload))
        return True


def add_device(client, auth, token="phone-1"):
    """Register an FCM token for the signed-in user."""
    assert client.post(f"{API}/devices", json={"fcm_token": token}, headers=auth).status_code in (200, 201, 204)


def add_todo(client, auth, deadline: datetime, **body):
    """Create a todo with `deadline` and return it."""
    response = client.post(f"{API}/todos", headers=auth,
                           json={"title": "Nộp báo cáo", "deadline_at": deadline.isoformat(), **body})
    assert response.status_code == 201, response.text
    return response.json()


def deadline_in_days(days: int, hour: int = 17) -> datetime:
    """A local deadline `days` from today at `hour`:00."""
    return datetime.combine(datetime.now(TZ).date() + timedelta(days=days), time(hour), TZ)


def test_deadline_reminders_fire_at_each_hours_before(client, auth):
    add_device(client, auth)
    deadline = deadline_in_days(3)
    todo = add_todo(client, auth, deadline)
    sender = FakeSender()

    for hours in (24, 2):  # default deadline_reminder_hours_before
        sender.sent.clear()
        assert run_send_reminders(deadline - timedelta(hours=hours, minutes=-1), sender) == {"sent": 1}
        [(token, payload)] = sender.sent
        assert token == "phone-1"
        assert PAYLOAD_KEYS <= payload.keys()
        assert (payload["type"], payload["ref_id"], payload["deep_link"]) == (
            "deadline", todo["id"], f"recolly://todos/{todo['id']}")
        assert payload["title"].startswith(f"Còn {hours} giờ")
    assert run_send_reminders(deadline - timedelta(hours=3), sender) == {}  # no trigger in that window


def test_no_deadline_reminder_for_done_todos_or_when_disabled(client, auth):
    add_device(client, auth)
    deadline = deadline_in_days(3)
    todo = add_todo(client, auth, deadline)
    at_trigger = deadline - timedelta(hours=2, minutes=-1)

    client.put(f"{API}/reminder-settings", json={"deadline_reminder_enabled": False}, headers=auth)
    assert run_send_reminders(at_trigger, FakeSender()) == {}
    client.put(f"{API}/reminder-settings", json={}, headers=auth)
    client.patch(f"{API}/todos/{todo['id']}", json={"status": "done"}, headers=auth)
    assert run_send_reminders(at_trigger, FakeSender()) == {}


def test_quiet_hours_drop_reminders(client, auth):
    add_device(client, auth)
    deadline = deadline_in_days(3, hour=3)  # 2 h before = 01:00, inside 23:00–07:00
    add_todo(client, auth, deadline)
    client.put(f"{API}/reminder-settings", json={"quiet_hours": {"start": "23:00", "end": "07:00"}}, headers=auth)
    assert run_send_reminders(deadline - timedelta(hours=2, minutes=-1), FakeSender()) == {}


def test_bedtime_reminder_comes_minutes_before_recommended_sleep(client, auth, db, user):
    client.put(f"{API}/health-profile", headers=auth, json={
        "usual_sleep_time": "23:00", "usual_wake_time": "06:30", "chronotype": "bear"})
    db.expire_all()
    start = datetime.now(TZ)
    due = [p for p in due_reminders(db, db.get(type(user), user.id), start, start + timedelta(days=1))
           if p["type"] == "bedtime"]
    assert due
    for payload in due:
        assert PAYLOAD_KEYS <= payload.keys()
        trigger = datetime.fromisoformat(payload["scheduled_for"]) - timedelta(minutes=30)  # default
        assert start <= trigger < start + timedelta(days=1)


def test_dead_token_is_removed(client, auth):
    add_device(client, auth, "dead-token")
    add_device(client, auth, "phone-1")
    deadline = deadline_in_days(3)
    add_todo(client, auth, deadline)
    add_todo(client, auth, deadline, title="Ôn thi")
    sender = FakeSender()
    counts = run_send_reminders(deadline - timedelta(hours=2, minutes=-1), sender)
    assert counts == {"sent": 2, "dead_tokens": 1}  # dead token tried once, then skipped
    assert {token for token, _ in sender.sent} == {"phone-1"}
    sender.sent.clear()
    assert run_send_reminders(deadline - timedelta(hours=2, minutes=-1), sender) == {"sent": 2}


# ─────────────────────────── FcmSender ───────────────────────────

@pytest.fixture
def service_account():
    """A throwaway service account with a fresh RSA key."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    return {"project_id": "recolly-test", "client_email": "push@recolly-test.iam.gserviceaccount.com",
            "token_uri": "https://oauth2.googleapis.com/token", "private_key": pem,
            "public_key": key.public_key()}


def test_fcm_sender_follows_the_v1_api(service_account):
    requests: list[httpx.Request] = []

    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.host == "oauth2.googleapis.com":
            return httpx.Response(200, json={"access_token": "ya29.test", "expires_in": 3600})
        token = json.loads(request.content)["message"]["token"]
        if token == "gone":
            return httpx.Response(404, json={"error": {"status": "NOT_FOUND", "details": [
                {"errorCode": "UNREGISTERED"}]}})
        return httpx.Response(200, json={"name": "projects/recolly-test/messages/1"})

    sender = FcmSender(service_account, httpx.Client(transport=httpx.MockTransport(handle)))
    payload = {"type": "deadline", "title": "Còn 2 giờ", "body": "…", "deep_link": "recolly://todos/1",
               "scheduled_for": "2026-11-20T17:00:00+07:00"}
    assert sender.send("phone-1", payload) is True
    assert sender.send("gone", payload) is False

    token_request, first, second = requests  # the access token is fetched once and reused
    form = dict(httpx.QueryParams(token_request.content.decode()))
    assert form["grant_type"] == "urn:ietf:params:oauth:grant-type:jwt-bearer"
    claims = jwt.decode(form["assertion"], service_account["public_key"], algorithms=["RS256"],
                        audience="https://oauth2.googleapis.com/token")
    assert claims["iss"] == service_account["client_email"]
    assert claims["scope"] == "https://www.googleapis.com/auth/firebase.messaging"
    assert str(first.url) == "https://fcm.googleapis.com/v1/projects/recolly-test/messages:send"
    assert first.headers["Authorization"] == "Bearer ya29.test"
    message = json.loads(first.content)["message"]
    assert message["notification"] == {"title": "Còn 2 giờ", "body": "…"}
    assert message["data"] == payload  # all values are strings already
