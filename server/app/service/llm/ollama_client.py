"""Chat with a self-hosted Ollama model (local machine or a Kaggle notebook behind a tunnel)."""

import json
import logging
import os
import time

import httpx

DEFAULT_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
DEFAULT_MODEL_NAME = os.getenv("OLLAMA_MODEL", "gemma3:4b")
DEFAULT_TIMEOUT_SECONDS = float(os.getenv("OLLAMA_TIMEOUT_SECONDS", "60"))

logger = logging.getLogger(__name__)


class OllamaError(Exception):
    """Raised when Ollama is unreachable or returns an unusable answer."""


class OllamaClient:
    """Sends chat requests to one Ollama server and returns the model's answer."""

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        model_name: str = DEFAULT_MODEL_NAME,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        transport: httpx.BaseTransport | None = None,
    ):
        """Remember which server and model to use (transport is only for tests)."""
        self.model_name = model_name
        self._http = httpx.Client(
            base_url=base_url.rstrip("/"),
            timeout=timeout_seconds,
            transport=transport,
        )

    def generate_text(
        self,
        system_prompt: str,
        user_message: str,
        temperature: float = 0.7,
        model_name: str | None = None,
    ) -> str:
        """Return the model's free-text reply to one user message."""
        return self._send_chat_request(system_prompt, user_message, temperature, model_name, None)

    def generate_json(
        self,
        system_prompt: str,
        user_message: str,
        json_schema: dict,
        model_name: str | None = None,
    ) -> dict:
        """Return a reply that Ollama constrains to the given JSON schema."""
        # Temperature 0 keeps extraction (e.g. transcript -> todo) repeatable
        reply = self._send_chat_request(system_prompt, user_message, 0.0, model_name, json_schema)
        try:
            return json.loads(reply)
        except json.JSONDecodeError as error:
            raise OllamaError(f"Model did not return valid JSON: {reply[:200]}") from error

    def list_model_names(self) -> list[str]:
        """Return the models already pulled on the server (also a health check)."""
        response = self._send_request("GET", "/api/tags")
        return [model["name"] for model in response.get("models", [])]

    def _send_chat_request(
        self,
        system_prompt: str,
        user_message: str,
        temperature: float,
        model_name: str | None,
        json_schema: dict | None,
    ) -> str:
        """Call POST /api/chat without streaming and return the reply text."""
        payload = {
            "model": model_name or self.model_name,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            "stream": False,
            "options": {"temperature": temperature},
        }
        if json_schema is not None:
            payload["format"] = json_schema

        response = self._send_request("POST", "/api/chat", payload)
        try:
            return response["message"]["content"].strip()
        except (KeyError, TypeError) as error:
            raise OllamaError(f"Unexpected Ollama response: {response}") from error

    def _send_request(self, method: str, path: str, payload: dict | None = None) -> dict:
        """Send one HTTP request and turn network/HTTP failures into OllamaError."""
        # Host only (e.g. the Kaggle trycloudflare tunnel), so the log shows whether the tunnel is alive.
        started, host = time.perf_counter(), self._http.base_url.host
        try:
            response = self._http.request(method, path, json=payload)
            response.raise_for_status()
            result = response.json()
        except httpx.HTTPStatusError as error:
            detail = error.response.text[:200]
            logger.warning("Ollama %s %s via %s failed: HTTP %d", method, path, host, error.response.status_code)
            raise OllamaError(f"Ollama returned {error.response.status_code}: {detail}") from error
        except (httpx.HTTPError, ValueError) as error:
            logger.warning("Ollama %s %s via %s unreachable: %s", method, path, host, error)
            raise OllamaError(f"Could not reach Ollama: {error}") from error
        logger.info("Ollama %s %s via %s ok in %.0fms", method, path, host, (time.perf_counter() - started) * 1000)
        return result
