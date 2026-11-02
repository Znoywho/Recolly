import uuid
from collections.abc import Sequence
from typing import Annotated

from fastapi import APIRouter, Query, Response
from pydantic import AwareDatetime
from sqlalchemy.orm import Session

from app.core.deps import CurrentUser, DbSession, response_context
from app.core.errors import ApiError, not_found
from app.core.timeutil import now_utc
from app.models.enums import TodoCategory, TodoStatus
from app.models.todo import Todo
from app.models.user import User
from app.repository.todo_repository import TodoRepository, decode_cursor, encode_cursor
from app.schemas.todo import TodoInput, TodoPage, TodoRead, TodoSort, TodoUpdate

router = APIRouter(prefix="/todos", tags=["Todos"])


def todo_reads(db: Session, user: User, todos: Sequence[Todo]) -> list[TodoRead]:
    minutes = TodoRepository(db).scheduled_minutes(t.id for t in todos)
    ctx = response_context(user)
    return [TodoRead.model_validate({**_columns(todo), "scheduled_minutes": minutes.get(todo.id, 0)},
                                    context=ctx) for todo in todos]


def _columns(todo: Todo) -> dict:
    return {column.key: getattr(todo, column.key) for column in Todo.__table__.columns}


def _get_todo(db: Session, user: User, todo_id: uuid.UUID) -> Todo:
    todo = TodoRepository(db).get_owned(todo_id, user.id)
    if todo is None:
        raise not_found("todo")
    return todo


@router.get("", response_model=TodoPage)
def list_todos(
    user: CurrentUser,
    db: DbSession,
    status: Annotated[list[TodoStatus] | None, Query(description="Repeatable.")] = None,
    category: TodoCategory | None = None,
    due_before: AwareDatetime | None = None,
    due_after: AwareDatetime | None = None,
    sort: TodoSort = "deadline_at",
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: str | None = None,
):
    """D1 · One page of todos. Without a deadline they sort last for `deadline_at`."""
    try:
        offset = decode_cursor(cursor)
    except ValueError:
        raise ApiError(400, "INVALID_CURSOR", "Unknown cursor") from None
    todos, more = TodoRepository(db).page(user.id, statuses=status or (), category=category,
                                          due_before=due_before, due_after=due_after, sort=sort,
                                          offset=offset, limit=limit)
    return TodoPage(items=todo_reads(db, user, todos),
                    next_cursor=encode_cursor(offset + limit) if more else None)


@router.post("", response_model=TodoRead, status_code=201)
def create_todo(body: TodoInput, user: CurrentUser, db: DbSession):
    """D2 · Create a todo."""
    todo = TodoRepository(db).create(Todo(user_id=user.id, **body.model_dump()))
    return todo_reads(db, user, [todo])[0]


@router.get("/{id}", response_model=TodoRead)
def get_todo(id: uuid.UUID, user: CurrentUser, db: DbSession):
    """D3 · Todo detail."""
    return todo_reads(db, user, [_get_todo(db, user, id)])[0]


@router.patch("/{id}", response_model=TodoRead)
def update_todo(id: uuid.UUID, body: TodoUpdate, user: CurrentUser, db: DbSession):
    """D4 · Edit a todo; `status = done` sets `completed_at`, any other status clears it."""
    todo = _get_todo(db, user, id)
    changes = body.changes()
    for field, value in changes.items():
        setattr(todo, field, value)
    if todo.start_at and todo.end_at and todo.end_at <= todo.start_at:
        raise ApiError(400, "INVALID_RANGE", "end_at must be after start_at")
    if "status" in changes:
        if todo.status is TodoStatus.DONE:
            todo.completed_at = todo.completed_at or now_utc()
        else:
            todo.completed_at = None
    db.flush()
    return todo_reads(db, user, [todo])[0]


@router.delete("/{id}", status_code=204)
def delete_todo(id: uuid.UUID, user: CurrentUser, db: DbSession):
    """D5 · Delete a todo; its study events stay with `todo_id = null`."""
    db.delete(_get_todo(db, user, id))
    db.flush()
    return Response(status_code=204)
