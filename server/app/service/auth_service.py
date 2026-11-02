"""Google sign-in and backend token pairs (R08)."""

import logging
from datetime import timedelta
from typing import Any

from sqlalchemy.orm import Session

from app.config import Config
from app.core.errors import ApiError
from app.core.security import create_access_token, hash_token, new_refresh_token
from app.core.timeutil import now_utc
from app.models.auth import RefreshToken
from app.models.user import User
from app.repository.refresh_token_repository import RefreshTokenRepository
from app.repository.user_repository import UserRepository
from app.service import calendar_sync
from app.service.google import CALENDAR_SCOPE, GoogleClient, GoogleGrant

logger = logging.getLogger(__name__)


def issue_tokens(db: Session, user: User) -> dict[str, Any]:
    token = new_refresh_token()
    RefreshTokenRepository(db).create(RefreshToken(
        user_id=user.id,
        token_hash=hash_token(token),
        expires_at=now_utc() + timedelta(days=Config.REFRESH_TOKEN_TTL_DAYS),
    ))
    return {"access_token": create_access_token(user.id), "refresh_token": token,
            "token_type": "bearer", "expires_in": Config.ACCESS_TOKEN_TTL_SECONDS}


def sign_in(db: Session, grant: GoogleGrant) -> tuple[User, bool]:
    """A1: find or create the user of a Google account; link Calendar if its scope was granted."""
    users = UserRepository(db)
    user = users.get_by_google_sub(grant.sub)
    is_new = user is None
    if user is None:
        user = users.create(User(google_sub=grant.sub, email=grant.email,
                                 display_name=(grant.name or "")[:100] or None,
                                 avatar_url=grant.picture))
    else:
        user.email = grant.email
        if grant.picture:
            user.avatar_url = grant.picture
    user.last_login_at = now_utc()
    if CALENDAR_SCOPE in grant.scopes:
        try:
            calendar_sync.save_connection(db, user, grant)
        except ApiError as exc:  # e.g. no TOKEN_ENCRYPTION_KEY: sign in anyway, connect later (G6)
            logger.warning("Calendar not linked at sign-in: %s", exc.detail)
    db.flush()
    return user, is_new


def refresh(db: Session, token: str) -> dict[str, Any]:
    """A2: refresh tokens rotate; reusing an old one ends every session of the user."""
    tokens = RefreshTokenRepository(db)
    row = tokens.get_by_hash(hash_token(token))
    now = now_utc()
    invalid = ApiError(401, "REFRESH_TOKEN_INVALID", "Refresh token is invalid, expired or already used")
    if row is None or row.expires_at <= now:
        raise invalid
    if row.revoked_at is not None:
        tokens.revoke_all(row.user_id, now)
        db.commit()  # keep the revocation although the request fails
        raise invalid
    row.revoked_at = now
    return issue_tokens(db, db.get(User, row.user_id))


def logout(db: Session, user: User, token: str) -> None:
    row = RefreshTokenRepository(db).get_by_hash(hash_token(token))
    if row is not None and row.user_id == user.id and row.revoked_at is None:
        row.revoked_at = now_utc()
        db.flush()


def delete_account(db: Session, user: User, google: GoogleClient) -> None:
    """U3: revoke Google access, then delete every row of the user (cascades)."""
    calendar_sync.disconnect(db, user, google)
    db.delete(user)
    db.flush()
