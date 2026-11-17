import os
from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.config import Config

engine = create_engine(
    Config.POSTGRES_DATABASE_URI,
    echo=os.getenv("SQL_ECHO", "false").lower() == "true",
    pool_pre_ping=True,
    pool_recycle=1800,
)

SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """FastAPI dependency: one session per request, closed after the response is sent.

    Commit/rollback lives in `app.core.deps.commit_when_endpoint_returns`, which runs earlier.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
