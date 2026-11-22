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

    def set_if_absent(self, key: str, value: str, seconds: int) -> bool:
        """Atomically store `value` only if `key` does not exist (SET NX EX); True when stored."""
        return bool(self.client.set(key, value, ex=seconds, nx=True))

    def increment_with_ttl(self, key: str, seconds: int) -> int:
        """Add 1 to the counter at `key` and return it; the TTL is set only by the first increment."""
        pipe = self.client.pipeline()  # MULTI/EXEC: INCR and EXPIRE NX run together
        pipe.incr(key)
        pipe.expire(key, seconds, nx=True)
        return pipe.execute()[0]

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

    def set_if_absent(self, key: str, value: str, seconds: int) -> bool:
        """Store `value` only if `key` is missing or expired; True when stored (one process, so no race)."""
        if self.get(key) is not None:
            return False
        self.set_with_ttl(key, value, seconds)
        return True

    def increment_with_ttl(self, key: str, seconds: int) -> int:
        """Add 1 to the counter at `key` and return it; a missing or expired counter restarts at 1 with a new TTL.

        shortcut: not thread-safe, so parallel requests may lose a count; dev/tests only, Redis when it matters.
        """
        if self.get(key) is None:
            self.set_with_ttl(key, "1", seconds)
            return 1
        value, expiry = self._items[key]
        self._items[key] = (str(int(value) + 1), expiry)
        return int(value) + 1

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
