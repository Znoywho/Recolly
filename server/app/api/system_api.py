import socket
from urllib.parse import urlparse

from fastapi import APIRouter, Response
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.config import Config
from app.core.deps import DbSession
from app.schemas.system import HealthStatus

router = APIRouter(tags=["System"])


def _redis_ok() -> bool:
    """Plain RESP PING, so the health check needs no Redis client library."""
    if not Config.REDIS_URL:
        return False
    url = urlparse(Config.REDIS_URL)
    try:
        with socket.create_connection((url.hostname or "localhost", url.port or 6379), timeout=1) as sock:
            if url.password:
                sock.sendall(f"AUTH {url.password}\r\n".encode())
                sock.recv(64)
            sock.sendall(b"PING\r\n")
            return sock.recv(64).startswith(b"+PONG")
    except OSError:
        return False


@router.get("/health", response_model=HealthStatus, openapi_extra={"security": []},
            responses={503: {"model": HealthStatus, "description": "A dependency is down."}})
def health_check(db: DbSession, response: Response):
    """X1 · Liveness / readiness. Redis only counts when REDIS_URL is configured."""
    try:
        db.execute(text("SELECT 1"))
        db_ok = True
    except SQLAlchemyError:
        db.rollback()
        db_ok = False
    redis_ok = _redis_ok()
    ok = db_ok and (redis_ok or not Config.REDIS_URL)
    if not ok:
        response.status_code = 503
    return HealthStatus(status="ok" if ok else "degraded", db="ok" if db_ok else "down",
                        redis="ok" if redis_ok else "down", version=Config.APP_VERSION)
