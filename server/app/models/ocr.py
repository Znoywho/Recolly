import uuid
from typing import TYPE_CHECKING, Any

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SystemTimeStamp, UUIDPrimaryKey
from app.models.enums import JobStatus, str_enum

if TYPE_CHECKING:
    from app.models.user import User


class OcrJob(UUIDPrimaryKey, SystemTimeStamp, Base):
    """Async timetable OCR job (Vintern). Flutter polls GET /ocr/jobs/{id}."""

    __tablename__ = "ocr_jobs"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    status: Mapped[JobStatus] = mapped_column(str_enum(JobStatus), default=JobStatus.QUEUED)
    image_path: Mapped[str] = mapped_column(String(1024))
    # Raw model output kept for debugging / OCR evaluation (R12).
    raw_output: Mapped[str | None] = mapped_column(Text)
    # Normalised result: {"subjects": [...]} as described in docs/api-v1.md.
    result: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    # OCR_NO_TABLE_FOUND | OCR_LOW_QUALITY | OCR_MODEL_ERROR
    error_code: Mapped[str | None] = mapped_column(String(64))

    user: Mapped["User"] = relationship(back_populates="ocr_jobs")
