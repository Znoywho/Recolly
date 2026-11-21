"""Per-caller request limits (fixed window) kept in the shared store.

Used twice: every /api/v1 route (`api_router`) and, tighter, on expensive routes such as
POST /schedule/generate. Over the limit: 429 RATE_LIMITED with Retry-After.
"""

import time
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.errors import ApiError
from app.core.redis_client import MemoryStore, RedisStore, get_store
from app.core.security import decode_access_token

_bearer = HTTPBearer(auto_error=False)


def caller_identity(request: Request, credentials: HTTPAuthorizationCredentials | None) -> str:
    """`user:<id>` for a valid access token (no DB lookup), else `ip:<client address>`."""
    if credentials is not None:
        try:
            return f"user:{decode_access_token(credentials.credentials)}"
        except ApiError:
            pass  # bad or expired token: count by IP; the route's own auth answers 401
    return f"ip:{request.client.host if request.client else 'unknown'}"


def rate_limit(name: str, limit: int, per_seconds: int = 60) -> Callable[..., None]:
    """FastAPI dependency: at most `limit` calls per caller in each `per_seconds` window."""

    def check_rate_limit(
        request: Request,
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
        store: Annotated[RedisStore | MemoryStore, Depends(get_store)],
    ) -> None:
        """Count this call; raise 429 once the window's count passes `limit`."""
        now = time.time()
        window = int(now // per_seconds)
        key = f"rl:{name}:{caller_identity(request, credentials)}:{window}"
        if store.increment_with_ttl(key, per_seconds) > limit:
            retry_after = max(1, int(per_seconds - now % per_seconds))
            raise ApiError(429, "RATE_LIMITED", f"Too many requests, try again in {retry_after} s",
                           headers={"Retry-After": str(retry_after)})

    return check_rate_limit
