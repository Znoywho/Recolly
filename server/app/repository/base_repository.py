import uuid
from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session


class BaseRepository[T]:
    """Generic data access. Never commits: the transaction is owned by `get_db`."""

    def __init__(self, model: type[T], session: Session):
        self.model = model
        self.session = session

    def get_by_id(self, id: uuid.UUID) -> T | None:
        return self.session.get(self.model, id)

    def get_all(self, limit: int = 100, offset: int = 0) -> Sequence[T]:
        statement = select(self.model).limit(limit).offset(offset)
        return self.session.scalars(statement).all()

    def create(self, instance: T) -> T:
        self.session.add(instance)
        self.session.flush()
        return instance

    def update(self, instance: T, **kwargs) -> T:
        for key, value in kwargs.items():
            setattr(instance, key, value)
        self.session.flush()
        return instance

    def delete(self, id: uuid.UUID) -> bool:
        instance = self.get_by_id(id)
        if instance is None:
            return False
        self.session.delete(instance)
        self.session.flush()
        return True
