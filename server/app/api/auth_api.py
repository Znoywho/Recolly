from fastapi import APIRouter, Response

from app.core.deps import CurrentUser, DbSession, response_context
from app.core.errors import ApiError
from app.schemas.user import AuthResponse, GoogleSignInRequest, RefreshRequest, TokenPair, UserRead
from app.service import auth_service, calendar_sync
from app.service.google import GoogleDep, GoogleError, GoogleUnavailable

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/google", response_model=AuthResponse, openapi_extra={"security": []})
def sign_in_with_google(body: GoogleSignInRequest, db: DbSession, google: GoogleDep):
    """A1 · Exchange the `serverAuthCode` from google_sign_in and issue backend JWTs."""
    try:
        grant = google.exchange_code(body.server_auth_code)
    except GoogleUnavailable as exc:
        raise calendar_sync.api_error(exc) from exc
    except GoogleError as exc:
        raise ApiError(400, "GOOGLE_CODE_INVALID", "Google rejected the server_auth_code") from exc
    user, is_new = auth_service.sign_in(db, grant)
    tokens = auth_service.issue_tokens(db, user)
    user_read = UserRead.model_validate(user, context=response_context(user))
    return AuthResponse(**tokens, user=user_read, is_new_user=is_new)


@router.post("/refresh", response_model=TokenPair, openapi_extra={"security": []})
def refresh_token(body: RefreshRequest, db: DbSession):
    """A2 · Refresh tokens rotate: the old one is invalid after use."""
    return TokenPair(**auth_service.refresh(db, body.refresh_token))


@router.post("/logout", status_code=204)
def logout(body: RefreshRequest, user: CurrentUser, db: DbSession):
    """A3 · Revoke a refresh token."""
    auth_service.logout(db, user, body.refresh_token)
    return Response(status_code=204)
