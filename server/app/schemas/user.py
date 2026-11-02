from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.core.timeutil import is_valid_timezone
from app.schemas.common import ORMModel, PatchModel


class UserRead(ORMModel):
    id: UUID
    email: str
    display_name: str | None
    avatar_url: str | None
    date_of_birth: date | None
    timezone: str
    google_calendar_connected: bool
    onboarding_completed: bool
    created_at: datetime
    last_login_at: datetime | None


class UserUpdate(PatchModel):
    non_nullable = frozenset({"timezone"})

    display_name: str | None = Field(default=None, max_length=100)
    date_of_birth: date | None = None
    timezone: str | None = Field(default=None, max_length=64, description="IANA name.")

    @field_validator("timezone")
    @classmethod
    def _known_timezone(cls, value: str | None) -> str | None:
        if value is not None and not is_valid_timezone(value):
            raise ValueError("unknown IANA timezone")
        return value


class GoogleSignInRequest(BaseModel):
    server_auth_code: str = Field(min_length=1)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int


class AuthResponse(TokenPair):
    user: UserRead
    is_new_user: bool
