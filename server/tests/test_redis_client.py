"""MemoryStore behaves like Redis keys with a TTL (no Redis needed)."""

from app.core import redis_client
from app.core.redis_client import MemoryStore


def test_set_get_delete():
    store = MemoryStore()
    store.set_with_ttl("k", "v", 60)
    assert store.get("k") == "v"
    store.delete("k")
    assert store.get("k") is None
    store.delete("k")  # deleting a missing key is fine


def test_value_expires_after_its_ttl(monkeypatch):
    clock = [1000.0]
    monkeypatch.setattr(redis_client.time, "monotonic", lambda: clock[0])
    store = MemoryStore()
    store.set_with_ttl("k", "v", 10)
    clock[0] += 9.9
    assert store.get("k") == "v"
    clock[0] += 0.1
    assert store.get("k") is None
