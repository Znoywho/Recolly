"""Short-lived key-value store: Redis when REDIS_URL is set, else an in-process dict.

The dict is only correct for one API process (dev and tests); with several workers or
after a restart, set REDIS_URL so every process sees the same keys.
"""

import time
from functools import cache

import redis

from app.config import Config


class RedisStore:
    """Keys with a time-to-live, shared by every API process through Redis."""

    def __init__(self, url: str):
        self.client = redis.Redis.from_url(url, decode_responses=True)

    def set_with_ttl(self, key: str, value: str, seconds: int) -> None:
        """Store `value`; Redis deletes it after `seconds`."""
        self.client.set(key, value, ex=seconds)

    def get(self, key: str) -> str | None:
        """The value, or None when missing or expired."""
        return self.client.get(key)

    def delete(self, key: str) -> None:
        """Remove the key if it exists."""
        self.client.delete(key)


class MemoryStore:
    """Same interface as RedisStore, kept in this process (no Redis needed)."""

    def __init__(self):
        self._items: dict[str, tuple[str, float]] = {}  # key -> (value, expiry as time.monotonic())

    def set_with_ttl(self, key: str, value: str, seconds: int) -> None:
        """Store `value` until `seconds` from now."""
        self._items[key] = (value, time.monotonic() + seconds)

    def get(self, key: str) -> str | None:
        """The value, or None when missing or expired (expired keys are dropped on read)."""
        item = self._items.get(key)
        if item is None:
            return None
        if item[1] <= time.monotonic():
            del self._items[key]
            return None
        return item[0]

    def delete(self, key: str) -> None:
        """Remove the key if it exists."""
        self._items.pop(key, None)


@cache
def get_store() -> RedisStore | MemoryStore:
    """The process-wide store: Redis if REDIS_URL is configured, else memory."""
    return RedisStore(Config.REDIS_URL) if Config.REDIS_URL else MemoryStore()
