"""Backend JWTs, opaque refresh tokens and encryption of stored Google tokens."""

import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from cryptography.fernet import Fernet

from app.config import Config
from app.core.errors import BEARER_CHALLENGE, ApiError

ALGORITHM = "HS256"


def create_access_token(user_id: uuid.UUID) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "type": "access",
        "iat": now,
        "exp": now + timedelta(seconds=Config.ACCESS_TOKEN_TTL_SECONDS),
    }
    return jwt.encode(payload, Config.JWT_SECRET, algorithm=ALGORITHM)


def decode_access_token(token: str) -> uuid.UUID:
    invalid = ApiError(401, "TOKEN_INVALID", "Invalid token", headers=BEARER_CHALLENGE)
    try:
        payload = jwt.decode(token, Config.JWT_SECRET, algorithms=[ALGORITHM],
                             options={"require": ["sub", "exp"]})
    except jwt.ExpiredSignatureError:
        raise ApiError(401, "TOKEN_EXPIRED", "Token expired", headers=BEARER_CHALLENGE) from None
    except jwt.PyJWTError:
        raise invalid from None
    if payload.get("type") != "access":
        raise invalid
    try:
        return uuid.UUID(payload["sub"])
    except ValueError:
        raise invalid from None


def new_refresh_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    """Refresh tokens are stored as SHA-256 hashes only."""
    return hashlib.sha256(token.encode()).hexdigest()


def _fernet() -> Fernet:
    if not Config.TOKEN_ENCRYPTION_KEY:
        raise ApiError(503, "GOOGLE_UNAVAILABLE", "TOKEN_ENCRYPTION_KEY is not configured on the server")
    return Fernet(Config.TOKEN_ENCRYPTION_KEY)


def encrypt(text: str) -> str:
    return _fernet().encrypt(text.encode()).decode()


def decrypt(token: str) -> str:
    return _fernet().decrypt(token.encode()).decode()


def channel_token(channel_id: str) -> str:
    """Secret Google echoes back in X-Goog-Channel-Token (G5); derived, so it needs no column."""
    key = (Config.TOKEN_ENCRYPTION_KEY or Config.JWT_SECRET).encode()
    return hmac.new(key, f"channel:{channel_id}".encode(), hashlib.sha256).hexdigest()
