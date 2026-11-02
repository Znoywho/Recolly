from fastapi import APIRouter, Response

from app.core.deps import CurrentUser, DbSession, response_context
from app.schemas.user import UserRead, UserUpdate
from app.service import auth_service
from app.service.google import GoogleDep

router = APIRouter(prefix="/users", tags=["User"])


@router.get("/me", response_model=UserRead)
def get_me(user: CurrentUser):
    """U1 · Current user."""
    return UserRead.model_validate(user, context=response_context(user))


@router.patch("/me", response_model=UserRead)
def update_me(body: UserUpdate, user: CurrentUser, db: DbSession):
    """U2 · Update profile."""
    for field, value in body.changes().items():
        setattr(user, field, value)
    db.flush()
    return UserRead.model_validate(user, context=response_context(user))


@router.delete("/me", status_code=204)
def delete_me(user: CurrentUser, db: DbSession, google: GoogleDep):
    """U3 · Delete the account and all its data; Google access is revoked."""
    auth_service.delete_account(db, user, google)
    return Response(status_code=204)
