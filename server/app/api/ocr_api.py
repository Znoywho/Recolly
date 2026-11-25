"""OCR endpoints (contract: docs/openapi.yaml, T1 POST /ocr/timetable, T2 GET /ocr/jobs/{id}; R09–R11).

T1 saves the photo and answers 202 at once; Vintern + Ollama run in a background task.
The app polls T2 every ~2 s, shows the subjects for review, then saves them with T4 POST /timetable.
"""

import uuid
from datetime import timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, File, UploadFile

from app.core.deps import CurrentUser, DbSession
from app.core.errors import ApiError, not_found
from app.core.rate_limit import rate_limit
from app.core.timeutil import now_utc
from app.models.enums import JobStatus
from app.models.ocr import OcrJob
from app.schemas.timetable import OcrJobCreated, OcrJobRead
from app.service.ocr.ocr_jobs import create_job, delete_expired, process_job
from app.service.ocr.vintern_client import OcrUnavailable, VinternClient

MAX_IMAGE_BYTES = 10 * 1024 * 1024  # contract: max 10 MB
STUCK_AFTER = timedelta(minutes=10)  # a job still running this long lost its process (server restart)
HEIC_BRANDS = (b"heic", b"heix", b"hevc", b"heim", b"heis", b"mif1", b"msf1")

router = APIRouter(prefix="/ocr", tags=["OCR"])  # mounted under /api/v1 by app.api.api_router


def image_suffix(image: bytes) -> str | None:
    """'.jpg' / '.png' / '.heic' from the file's first bytes (the client's filename and type are not trusted)."""
    if image.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if image.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if image[4:8] == b"ftyp" and image[8:12] in HEIC_BRANDS:
        return ".heic"
    return None


@router.post("/timetable", status_code=202, response_model=OcrJobCreated,
             dependencies=[Depends(rate_limit("ocr", limit=10))])
async def upload_timetable_image(user: CurrentUser, db: DbSession, background: BackgroundTasks,
                                 image: UploadFile = File(...)):
    """T1 · Save the photo, queue OCR, return the job id to poll."""
    image_bytes = await image.read(MAX_IMAGE_BYTES + 1)  # never load more than the limit into memory
    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise ApiError(413, "FILE_TOO_LARGE", "Image larger than 10 MB")
    suffix = image_suffix(image_bytes)
    if suffix is None:
        raise ApiError(400, "UNSUPPORTED_IMAGE", "Image must be a JPEG, PNG or HEIC file")
    try:
        VinternClient.get_instance()
    except OcrUnavailable as error:
        raise ApiError(503, "OCR_UNAVAILABLE", "OCR model is not available") from error

    delete_expired(db, now_utc())  # lazy 24 h cleanup: no extra service needed
    job = create_job(db, user, image_bytes, suffix)
    background.add_task(process_job, job.id)
    return OcrJobCreated(job_id=job.id, status=job.status)


@router.get("/jobs/{job_id}", response_model=OcrJobRead)
def get_ocr_job(job_id: uuid.UUID, user: CurrentUser, db: DbSession) -> OcrJobRead:
    """T2 · Job state and, once succeeded, the parsed subjects."""
    job = db.get(OcrJob, job_id)
    if job is None or job.user_id != user.id:
        raise not_found("ocr_job")
    if job.status in (JobStatus.QUEUED, JobStatus.PROCESSING) and job.created_at < now_utc() - STUCK_AFTER:
        job.status, job.error_code = JobStatus.FAILED, "OCR_MODEL_ERROR"  # stop the app polling forever
    return OcrJobRead(job_id=job.id, status=job.status, error=job.error_code, result=job.result,
                      created_at=job.created_at)
