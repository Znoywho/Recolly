import uuid
from collections.abc import Sequence
from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.enums import EventKind, EventSource
from app.models.event import Event
from app.repository.base_repository import BaseRepository


class EventRepository(BaseRepository[Event]):
    def __init__(self, session: Session):
        super().__init__(Event, session)

    def list_candidates(self, user_id: uuid.UUID, start: datetime, end: datetime,
                        kind: EventKind | None = None,
                        source: EventSource | None = None) -> Sequence[Event]:
        """Events that may have an instance in [start, end): one-off events overlapping the
        range plus every recurring series that started before `end` (expanded by the caller)."""
        statement = select(Event).where(
            Event.user_id == user_id,
            Event.start_at < end,
            or_(Event.rrule.is_not(None), Event.end_at > start),
        )
        if kind is not None:
            statement = statement.where(Event.kind == kind)
        if source is not None:
            statement = statement.where(Event.source == source)
        return self.session.scalars(statement.order_by(Event.start_at)).all()

    def get_by_google_id(self, user_id: uuid.UUID, google_event_id: str) -> Event | None:
        statement = select(Event).where(Event.user_id == user_id,
                                        Event.google_event_id == google_event_id)
        return self.session.scalar(statement)
