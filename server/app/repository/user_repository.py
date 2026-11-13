from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.user import User
from app.repository.base_repository import BaseRepository


class UserRepository(BaseRepository[User]):
    def __init__(self, session: Session):
        super().__init__(User, session)

    def get_by_email(self, email: str) -> User | None:
        statement = select(User).where(User.email == email)
        return self.session.scalar(statement)

    def get_by_google_sub(self, google_sub: str) -> User | None:
        statement = select(User).where(User.google_sub == google_sub)
        return self.session.scalar(statement)
