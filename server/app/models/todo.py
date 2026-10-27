import uuid
from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey
from app.models.enums import Priority, TodoCategory, TodoStatus, str_enum


class Todo(UUIDPrimaryKey, SystemTimeStamp, Base):
    """A task or deadline. The CP-SAT scheduler needs deadline_at + estimated_minutes.

    `scheduled_minutes` in the API is computed from linked study events, not stored.
    """

    __tablename__ = "todos"
    __table_args__ = (
        CheckConstraint("difficulty IS NULL OR difficulty BETWEEN 1 AND 5", name="difficulty_range"),
        CheckConstraint(
            "estimated_minutes IS NULL OR estimated_minutes BETWEEN 1 AND 6000",
            name="estimated_minutes_range",
        ),
        CheckConstraint("end_at IS NULL OR start_at IS NULL OR end_at > start_at", name="end_after_start"),
        Index("ix_todos_user_id_status_deadline_at", "user_id", "status", "deadline_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text)
    category: Mapped[TodoCategory] = mapped_column(
        str_enum(TodoCategory), default=TodoCategory.OTHER
    )
    status: Mapped[TodoStatus] = mapped_column(str_enum(TodoStatus), default=TodoStatus.TODO)
    priority: Mapped[Priority] = mapped_column(str_enum(Priority), default=Priority.MEDIUM)
    deadline_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    estimated_minutes: Mapped[int | None] = mapped_column(Integer)
    difficulty: Mapped[int | None] = mapped_column(SmallInteger)  # 1-5; hard tasks go to peak alertness
    # Optional fixed time slot (todo that is not free for the scheduler to move).
    start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="todos")
    events: Mapped[list["Event"]] = relationship(back_populates="todo")
