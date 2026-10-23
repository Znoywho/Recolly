from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

from app.schemas.common import ORMModel


class UserRead(ORMModel):
    id: UUID
    email: EmailStr
    display_name: str | None
    avatar_url: str | None
    date_of_birth: date | None
    timezone: str
    created_at: datetime
    last_login_at: datetime | None


class UserUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=100)
    date_of_birth: date | None = None
    timezone: str | None = Field(default=None, max_length=64)
