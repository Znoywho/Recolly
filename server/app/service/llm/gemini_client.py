"""Chat with Google Gemini over plain REST (Interactions API, no SDK).

    https://aistudio.google.com/docs/image-understanding
    https://aistudio.google.com/api-reference/interactions-api

On the unpaid tier Google may use and review what is sent (https://aistudio.google.com/docs/terms):
send test data only, or enable billing before real users' data goes through it.
"""

import base64
import json
import logging
import os
import time

import httpx

API_URL = "https://generativelanguage.googleapis.com/v1beta/interactions"
API_REVISION = "2026-05-20"
DEFAULT_MODEL_NAME = "gemini-3.5-flash-lite"
TOKEN_FIELDS = ("total_input_tokens", "total_output_tokens", "total_thought_tokens", "total_tokens")

logger = logging.getLogger(__name__)


class GeminiError(Exception):
    """Any failed Gemini call."""


class GeminiRejected(GeminiError):
    """The request itself is wrong (key, model name, schema): trying again will not help."""


class GeminiUnavailable(GeminiError):
    """Network, server or rate-limit failure."""


class GeminiBadReply(GeminiError):
    """The model answered, but the answer is incomplete or not what was asked for."""


def reply_text(body: dict) -> str:
    """The output text: steps[type=model_output].content[type=text].text, joined."""
    return "".join(part.get("text", "")
                   for step in body.get("steps", []) if step.get("type") == "model_output"
                   for part in step.get("content", []) if part.get("type") == "text")


class GeminiClient:
    """Sends requests to one Gemini model and returns its answer."""

    def __init__(self, api_key: str | None = None, model_name: str | None = None, timeout_seconds: float = 60,
                 attempts: int = 1, wait_seconds: float = 30, transport: httpx.BaseTransport | None = None,
                 sleep=time.sleep):
        """Read GEMINI_API_KEY and GEMINI_MODEL when not given; `attempts` covers rate limits and server errors."""
        api_key = api_key or os.getenv("GEMINI_API_KEY", "")
        if not api_key:
            raise GeminiRejected("GEMINI_API_KEY is not set")
        self.model_name = model_name or os.getenv("GEMINI_MODEL") or DEFAULT_MODEL_NAME
        self.attempts, self.wait_seconds, self.sleep = attempts, wait_seconds, sleep
        self.last_tokens: dict[str, int] = {}  # token counts of the latest answer (read by the eval scripts)
        self._http = httpx.Client(timeout=timeout_seconds, transport=transport,
                                  headers={"x-goog-api-key": api_key, "Api-Revision": API_REVISION})

    def generate_text(self, system_prompt: str, user_message: str) -> str:
        """Return the model's free-text reply to one user message."""
        return self._create_interaction({"system_instruction": system_prompt, "input": user_message})

    def generate_json_from_image(self, system_prompt: str, request: str, image_bytes: bytes, mime_type: str,
                                 json_schema: dict) -> dict:
        """Return a reply about one image that Gemini constrains to the given JSON schema."""
        image = {"type": "image", "mime_type": mime_type, "data": base64.b64encode(image_bytes).decode("ascii")}
        reply = self._create_interaction({
            "system_instruction": system_prompt,
            "input": [{"type": "text", "text": request}, image],
            "response_format": {"type": "text", "mime_type": "application/json", "schema": json_schema},
        })
        try:
            parsed = json.loads(reply)
        except json.JSONDecodeError as error:
            raise GeminiBadReply("Gemini did not return valid JSON") from error
        if not isinstance(parsed, dict):
            raise GeminiBadReply("Gemini returned JSON that is not an object")
        return parsed

    def _create_interaction(self, payload: dict) -> str:
        """Send one interaction (not stored by Google for later retrieval) and return its text."""
        self.last_tokens = {}
        body = self._send({"model": self.model_name, **payload, "store": False})
        usage = body.get("usage") or {}
        self.last_tokens = {field: usage[field] for field in TOKEN_FIELDS if field in usage}
        if body.get("status") != "completed":
            raise GeminiBadReply(f"Gemini status={body.get('status')}")
        return reply_text(body)

    def _send(self, payload: dict) -> dict:
        """POST the request, waiting and retrying on 429 and server errors. Never logs the key or the content."""
        problem = ""
        for attempt in range(1, self.attempts + 1):
            try:
                response = self._http.post(API_URL, json=payload)
                if response.is_success:
                    return response.json()
                problem = f"HTTP {response.status_code}: {response.text[:400]}"
                if response.status_code != 429 and response.status_code < 500:
                    logger.error("Gemini rejected the request: %s", problem)
                    raise GeminiRejected(problem)
            except (httpx.HTTPError, ValueError) as error:
                problem = repr(error)
            if attempt < self.attempts:
                logger.warning("Gemini failed, retrying in %ss: %s", self.wait_seconds, problem[:150])
                self.sleep(self.wait_seconds)
        logger.warning("Gemini unavailable: %s", problem[:150])
        raise GeminiUnavailable(problem)
