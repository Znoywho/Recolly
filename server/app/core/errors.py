"""Error body of the API contract: every non-2xx except 422 is {"detail": "...", "code": "..."}.

Flutter branches on `code`, never on `detail`.
"""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)

BEARER_CHALLENGE = {"WWW-Authenticate": "Bearer"}

_HTTP_CODES = {
    400: "BAD_REQUEST",
    401: "TOKEN_INVALID",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
}


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, detail: str,
                 headers: dict[str, str] | None = None):
        super().__init__(detail)
        self.status_code = status_code
        self.code = code
        self.detail = detail
        self.headers = headers


def not_found(resource: str) -> ApiError:
    """not_found("sleep_log") -> 404 SLEEP_LOG_NOT_FOUND "Sleep log not found"."""
    name = resource.replace("_", " ")
    return ApiError(404, f"{resource.upper()}_NOT_FOUND", f"{name[0].upper()}{name[1:]} not found")


def validation_error(field: str, message: str) -> RequestValidationError:
    """422 in FastAPI's default body, for checks that need the database."""
    return RequestValidationError([{"loc": ("body", field), "msg": message, "type": "value_error"}])


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse({"detail": exc.detail, "code": exc.code},
                            status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(StarletteHTTPException)
    async def http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _HTTP_CODES.get(exc.status_code, "HTTP_ERROR")
        return JSONResponse({"detail": str(exc.detail), "code": code},
                            status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(Exception)
    async def unhandled(_: Request, exc: Exception) -> JSONResponse:
        logger.error("Unhandled error", exc_info=exc)
        return JSONResponse({"detail": "Internal server error", "code": "INTERNAL_ERROR"},
                            status_code=500)
