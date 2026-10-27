from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

from app.schemas.common import ORMModel

# {
#   "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
#   "email": "user@example.com",
#   "display_name": "string",
#   "avatar_url": "https://example.com/",
#   "date_of_birth": "2026-10-23",
#   "timezone": "Asia/Ho_Chi_Minh",
#   "google_calendar_connected": true,
#   "onboarding_completed": true,
#   "created_at": "2026-10-23T16:12:10.100Z",
#   "last_login_at": "2026-10-23T16:12:10.100Z"
# }

class UserRead(ORMModel):
    id: UUID
    email: EmailStr
    display_name: str | None
    avatar_url: str | None
    date_of_birth: date | None
    timezone: str
    google_calendar_connected: bool | None
    onboarding_completed: bool | None
    created_at: datetime
    last_login_at: datetime | None


class UserUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=100)
    date_of_birth: date | None = None
    timezone: str | None = Field(default=None, max_length=64)
