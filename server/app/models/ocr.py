# import uuid
# from typing import Any
#
# from sqlalchemy import ForeignKey, String
# from sqlalchemy.dialects.postgresql import JSONB
# from sqlalchemy.orm import Mapped, mapped_column
#
# from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
# from app.models.enums import JobStatus, str_enum
#
#
# class OcrJob(UUIDPrimaryKeyMixin, TimestampMixin, Base):
#     """Async timetable OCR job (Vintern). Flutter polls GET /ocr/jobs/{id}."""
#
#     __tablename__ = "ocr_jobs"
#
#     user_id: Mapped[uuid.UUID] = mapped_column(
#         ForeignKey("users.id", ondelete="CASCADE"), index=True
#     )
#     status: Mapped[JobStatus] = mapped_column(str_enum(JobStatus), default=JobStatus.QUEUED)
#     image_path: Mapped[str] = mapped_column(String(1024))
#     # Raw model output kept for debugging / OCR evaluation (R12).
#     raw_output: Mapped[str | None] = mapped_column(String)
#     # Normalised result: {"subjects": [...]} as described in docs/api-v1.md.
#     result: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
#     error_code: Mapped[str | None] = mapped_column(String(64))
