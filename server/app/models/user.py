from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class user(BaseModel):
    id: UUID
    email: str | None
    display_name: str | None
    avatar_url: str | None
    date_of_birth: str | None
 
