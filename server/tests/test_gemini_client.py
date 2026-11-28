"""The Gemini client, with the API replaced by an httpx mock."""

import json

import httpx
import pytest

from app.service.llm.gemini_client import GeminiBadReply, GeminiClient, GeminiRejected, GeminiUnavailable


def client_answering(*responses: httpx.Response, attempts: int = 1) -> tuple[GeminiClient, list]:
    queue, requests = list(responses), []

    def handle(request):
        requests.append(json.loads(request.content))
        return queue.pop(0)

    transport = httpx.MockTransport(handle)
    return GeminiClient("key", "m", attempts=attempts, transport=transport, sleep=lambda _: None), requests


def completed(text: str) -> httpx.Response:
    return httpx.Response(200, json={"status": "completed", "steps": [
        {"type": "model_output", "content": [{"type": "text", "text": text}]}]})


def test_text_request_is_not_stored():
    client, requests = client_answering(completed("xin chào"))

    assert client.generate_text("rules", "hi") == "xin chào"
    assert requests[0] == {"model": "m", "system_instruction": "rules", "input": "hi", "store": False}


def test_missing_key_is_rejected(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "")
    with pytest.raises(GeminiRejected):
        GeminiClient()


@pytest.mark.parametrize("response, error", [
    (httpx.Response(403, text="bad key"), GeminiRejected),
    (httpx.Response(429), GeminiUnavailable),
    (httpx.Response(200, text="not json"), GeminiUnavailable),
    (httpx.Response(200, json={"status": "failed"}), GeminiBadReply),
    (completed("[1]"), GeminiBadReply),
])
def test_failures_are_told_apart(response, error):
    client, _ = client_answering(response)
    with pytest.raises(error):
        client.generate_json_from_image("rules", "read", b"png", "image/png", {})


def test_server_errors_are_retried():
    client, requests = client_answering(httpx.Response(503), completed("ok"), attempts=2)

    assert client.generate_text("rules", "hi") == "ok" and len(requests) == 2
