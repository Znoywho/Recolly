import logging
import time
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Request

import app.models  # noqa: F401  register every table on Base.metadata
from app.api import api_router
from app.config import Config
from app.core.errors import install_error_handlers
from app.core.rate_limit import _bearer, caller_identity
from app.db.base import Base
from app.db.session import engine

# uvicorn only configures its own loggers; without this every app logger.info() is dropped.
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
request_logger = logging.getLogger("app.request")
QUIET_PATHS = {"/api/v1/health"}  # polled by healthchecks; would flood the log viewer


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Create missing tables until migrations (Alembic) are set up
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Recolly API", version=Config.APP_VERSION, lifespan=lifespan)
install_error_handlers(app)
app.include_router(api_router)


@app.middleware("http")
async def log_request(request: Request, call_next):
    """One line per request: method, path, status, duration and caller; level follows the status."""
    started = time.perf_counter()
    response = await call_next(request)
    if request.url.path not in QUIET_PATHS:
        elapsed_ms = (time.perf_counter() - started) * 1000
        level = (logging.ERROR if response.status_code >= 500
                 else logging.WARNING if response.status_code >= 400 else logging.INFO)
        request_logger.log(level, "%s %s %d %.0fms %s", request.method, request.url.path,
                           response.status_code, elapsed_ms,
                           caller_identity(request, await _bearer(request)))
    return response


@app.get("/")
def read_root():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8765, access_log=False)  # log_request replaces it
