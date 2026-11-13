"""In-memory stand-in for GoogleClient with the same method contract.

Calendars keep every event (deleted ones as `cancelled`) plus a change log, so syncToken
pulls return only what changed since the token was issued.
"""

import copy
import itertools
from datetime import UTC, datetime, timedelta
from typing import Any

from app.service.google import EventPage, GoogleAuthRevoked, GoogleError, GoogleGrant, GoogleUnavailable

CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.events"


class FakeGoogle:
    def __init__(self):
        self.grants: dict[str, GoogleGrant] = {}
        self.calendars: dict[str, dict[str, dict[str, Any]]] = {"primary": {}}
        self.changes: list[tuple[int, str, str]] = []  # (seq, calendar_id, event_id)
        self.channels: dict[str, str] = {}  # channel id -> resource id
        self.revoked_tokens: list[str] = []
        self.revoked = False
        self.down = False
        self._seq = itertools.count(1)
        self._ids = itertools.count(1)

    # ── test helpers ──

    def add_grant(self, code: str, *, sub: str, email: str, calendar: bool,
                  refresh_token: str | None = "google-refresh-token", name: str = "Sinh Viên") -> None:
        scopes = {"openid", "email", "profile"} | ({CALENDAR_SCOPE} if calendar else set())
        self.grants[code] = GoogleGrant(sub=sub, email=email, name=name, picture=None,
                                        refresh_token=refresh_token, scopes=frozenset(scopes))

    def events(self, calendar_id: str = "primary", *, include_cancelled: bool = False) -> list[dict]:
        return [e for e in self.calendars.get(calendar_id, {}).values()
                if include_cancelled or e["status"] != "cancelled"]

    def _touch(self, calendar_id: str, item: dict[str, Any]) -> None:
        seq = next(self._seq)
        item["etag"] = f'"{seq}"'
        item["updated"] = datetime.now(UTC).isoformat()
        self.changes.append((seq, calendar_id, item["id"]))

    def edit_on_google(self, event_id: str, calendar_id: str = "primary", **fields: Any) -> dict:
        item = self.calendars[calendar_id][event_id]
        item.update(fields)
        self._touch(calendar_id, item)
        return item

    def delete_on_google(self, event_id: str, calendar_id: str = "primary") -> None:
        item = self.calendars[calendar_id][event_id]
        item["status"] = "cancelled"
        self._touch(calendar_id, item)

    def add_on_google(self, summary: str, start: datetime, minutes: int = 60,
                      calendar_id: str = "primary", **fields: Any) -> dict:
        item = {"id": f"google{next(self._ids):04d}", "status": "confirmed", "summary": summary,
                "start": {"dateTime": start.isoformat()},
                "end": {"dateTime": (start + timedelta(minutes=minutes)).isoformat()}, **fields}
        self.calendars.setdefault(calendar_id, {})[item["id"]] = item
        self._touch(calendar_id, item)
        return item

    def _check(self, token: str) -> None:
        if self.down:
            raise GoogleUnavailable(503, "backendError")
        if self.revoked or token != "access-token":
            raise GoogleAuthRevoked(401, "authError")

    # ── GoogleClient contract ──

    def exchange_code(self, code: str) -> GoogleGrant:
        if self.down:
            raise GoogleUnavailable(503, "backendError")
        if code not in self.grants:
            raise GoogleError(400, "invalid_grant")
        return self.grants[code]

    def access_token(self, refresh_token: str) -> str:
        if self.down:
            raise GoogleUnavailable(0, "connection refused")
        if self.revoked:
            raise GoogleAuthRevoked(400, "invalid_grant")
        return "access-token"

    def revoke(self, token: str) -> None:
        self.revoked_tokens.append(token)

    def get_event(self, token: str, calendar_id: str, event_id: str) -> dict | None:
        self._check(token)
        item = self.calendars.get(calendar_id, {}).get(event_id)
        return copy.deepcopy(item) if item else None

    def insert_event(self, token: str, calendar_id: str, body: dict[str, Any]) -> dict:
        self._check(token)
        calendar = self.calendars.setdefault(calendar_id, {})
        event_id = body.get("id") or f"google{next(self._ids):04d}"
        if event_id in calendar:
            raise GoogleError(409, "duplicate")
        item = {k: v for k, v in body.items() if v is not None}
        item.update(id=event_id, status="confirmed")
        calendar[event_id] = item
        self._touch(calendar_id, item)
        return copy.deepcopy(item)

    def patch_event(self, token: str, calendar_id: str, event_id: str, body: dict[str, Any],
                    etag: str | None = None) -> dict:
        self._check(token)
        item = self.calendars.get(calendar_id, {}).get(event_id)
        if item is None or item["status"] == "cancelled":
            raise GoogleError(404, "notFound")
        if etag is not None and etag != item["etag"]:
            raise GoogleError(412, "conditionNotMet")
        for key, value in body.items():
            if value is None:
                item.pop(key, None)
            else:
                item[key] = value
        self._touch(calendar_id, item)
        return copy.deepcopy(item)

    def delete_event(self, token: str, calendar_id: str, event_id: str) -> None:
        self._check(token)
        item = self.calendars.get(calendar_id, {}).get(event_id)
        if item is not None and item["status"] != "cancelled":
            item["status"] = "cancelled"
            self._touch(calendar_id, item)

    def list_events(self, token: str, calendar_id: str, *, sync_token: str | None = None,
                    time_min: datetime | None = None, page_token: str | None = None) -> EventPage:
        self._check(token)
        calendar = self.calendars.get(calendar_id, {})
        if sync_token is None:
            items = [e for e in calendar.values() if e["status"] != "cancelled"]
        else:
            since = int(sync_token)
            changed = {eid for seq, cid, eid in self.changes if cid == calendar_id and seq > since}
            items = [calendar[eid] for eid in changed]
        last = max((seq for seq, *_ in self.changes), default=0)
        return EventPage(items=copy.deepcopy(items), next_page_token=None, next_sync_token=str(last))

    def can_write(self, token: str, calendar_id: str) -> bool:
        self._check(token)
        return calendar_id in self.calendars

    def watch(self, token: str, calendar_id: str, channel_id: str, channel_token: str,
              address: str) -> tuple[str, datetime]:
        self._check(token)
        self.channels[channel_id] = f"resource-{channel_id}"
        return self.channels[channel_id], datetime.now(UTC) + timedelta(days=7)

    def stop_channel(self, token: str, channel_id: str, resource_id: str) -> None:
        self.channels.pop(channel_id, None)
