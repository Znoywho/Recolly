"""FastAPI dependencies shared by every router."""

from collections.abc import Iterator
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.errors import BEARER_CHALLENGE, ApiError
from app.core.security import decode_access_token
from app.db.session import get_db
from app.models.user import User

_bearer = HTTPBearer(auto_error=False)

def commit_when_endpoint_returns(db: Annotated[Session, Depends(get_db)]) -> Iterator[Session]:
    """Commit as soon as the endpoint returns (rollback if it raises), before the response is sent.

    FastAPI runs request-scoped yield cleanup only after the response is sent, so committing
    there let a client's next request (e.g. right after sign-in) miss the new rows.
    """
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise


DbSession = Annotated[Session, Depends(commit_when_endpoint_returns, scope="function")]


def get_current_user(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    if credentials is None:
        raise ApiError(401, "TOKEN_INVALID", "Missing bearer token", headers=BEARER_CHALLENGE)
    user = db.get(User, decode_access_token(credentials.credentials))
    if user is None:
        raise ApiError(401, "TOKEN_INVALID", "User no longer exists", headers=BEARER_CHALLENGE)
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def user_tz(user: User) -> ZoneInfo:
    return ZoneInfo(user.timezone)


def response_context(user: User) -> dict:
    """Validation context that renders datetimes in the user's timezone (see ORMModel)."""
    return {"tz": user_tz(user)}
