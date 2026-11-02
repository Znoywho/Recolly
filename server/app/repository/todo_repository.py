import base64
import uuid
from collections.abc import Iterable, Sequence
from datetime import datetime

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.models.enums import EventKind, Priority, TodoCategory, TodoStatus
from app.models.event import Event
from app.models.todo import Todo
from app.repository.base_repository import BaseRepository

_PRIORITY_RANK = case({Priority.LOW: 0, Priority.MEDIUM: 1, Priority.HIGH: 2}, value=Todo.priority)
_SORTS = {
    "deadline_at": Todo.deadline_at.asc().nulls_last(),
    "-deadline_at": Todo.deadline_at.desc().nulls_last(),
    "priority": _PRIORITY_RANK.asc(),
    "-priority": _PRIORITY_RANK.desc(),
    "created_at": Todo.created_at.asc(),
    "-created_at": Todo.created_at.desc(),
}


def encode_cursor(offset: int) -> str:
    return base64.urlsafe_b64encode(f"o:{offset}".encode()).decode()


def decode_cursor(cursor: str | None) -> int:
    """Opaque cursor -> offset; ValueError if it was not issued by encode_cursor."""
    if not cursor:
        return 0
    kind, _, value = base64.urlsafe_b64decode(cursor.encode()).decode().partition(":")
    if kind != "o" or not value.isdigit():
        raise ValueError("bad cursor")
    return int(value)


class TodoRepository(BaseRepository[Todo]):
    def __init__(self, session: Session):
        super().__init__(Todo, session)

    def page(self, user_id: uuid.UUID, *, statuses: Iterable[TodoStatus] = (),
             category: TodoCategory | None = None, due_before: datetime | None = None,
             due_after: datetime | None = None, sort: str = "deadline_at", offset: int = 0,
             limit: int = 20) -> tuple[Sequence[Todo], bool]:
        """One page of todos and whether more follow."""
        statement = select(Todo).where(Todo.user_id == user_id)
        if statuses:
            statement = statement.where(Todo.status.in_(list(statuses)))
        if category is not None:
            statement = statement.where(Todo.category == category)
        if due_before is not None:
            statement = statement.where(Todo.deadline_at < due_before)
        if due_after is not None:
            statement = statement.where(Todo.deadline_at > due_after)
        statement = statement.order_by(_SORTS[sort], Todo.id).offset(offset).limit(limit + 1)
        rows = self.session.scalars(statement).all()
        return rows[:limit], len(rows) > limit

    def not_done(self, user_id: uuid.UUID, ids: Iterable[uuid.UUID] | None = None) -> Sequence[Todo]:
        statement = select(Todo).where(Todo.user_id == user_id, Todo.status != TodoStatus.DONE)
        if ids is not None:
            statement = statement.where(Todo.id.in_(list(ids)))
        return self.session.scalars(statement.order_by(Todo.deadline_at.asc().nulls_last())).all()

    def scheduled_minutes(self, todo_ids: Iterable[uuid.UUID]) -> dict[uuid.UUID, int]:
        """Minutes of study events linked to each todo."""
        ids = list(todo_ids)
        if not ids:
            return {}
        minutes = func.sum(func.extract("epoch", Event.end_at - Event.start_at) / 60)
        statement = (select(Event.todo_id, minutes)
                     .where(Event.todo_id.in_(ids), Event.kind == EventKind.STUDY)
                     .group_by(Event.todo_id))
        return {
            todo_id: int(total) for todo_id, total in self.session.execute(statement)
        }
