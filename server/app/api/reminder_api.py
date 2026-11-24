from fastapi import APIRouter, Response
from sqlalchemy import select

from app.core.deps import CurrentUser, DbSession, user_tz
from app.core.timeutil import now_utc
from app.models.enums import TodoStatus
from app.models.notification import Device, ReminderSettings as ReminderSettingsRow
from app.repository.todo_repository import TodoRepository
from app.schemas.notification import DeviceRegister, Quote, QuoteContext, ReminderSettings
from app.service import biorhythm_service
from app.service.quotes import llm_quote
from app.service.reminders import reminder_settings_of

router = APIRouter(tags=["Reminders"])


@router.get("/reminder-settings", response_model=ReminderSettings)
def get_reminder_settings(user: CurrentUser):
    """R1 · Reminder settings (defaults until the user saves them)."""
    return reminder_settings_of(user.reminder_settings)


@router.put("/reminder-settings", response_model=ReminderSettings)
def put_reminder_settings(body: ReminderSettings, user: CurrentUser, db: DbSession):
    """R2 · Replace reminder settings."""
    fields = {
        "bedtime_reminder_enabled": body.bedtime_reminder_enabled,
        "bedtime_reminder_minutes_before": body.bedtime_reminder_minutes_before,
        "deadline_reminder_enabled": body.deadline_reminder_enabled,
        "deadline_reminder_hours_before": body.deadline_reminder_hours_before,
        "kss_prompt_enabled": body.kss_prompt_enabled,
        "kss_prompts_per_day": body.kss_prompts_per_day,
        "kss_prompt_window_start": body.kss_prompt_window.start,
        "kss_prompt_window_end": body.kss_prompt_window.end,
        "sleep_confirm_enabled": body.sleep_confirm_enabled,
        "motivation_enabled": body.motivation_enabled,
        "quiet_hours_start": body.quiet_hours.start if body.quiet_hours else None,
        "quiet_hours_end": body.quiet_hours.end if body.quiet_hours else None,
    }
    row = user.reminder_settings
    if row is None:
        user.reminder_settings = row = ReminderSettingsRow(user_id=user.id, **fields)
    else:
        for field, value in fields.items():
            setattr(row, field, value)
    db.flush()
    return reminder_settings_of(row)


@router.post("/devices", status_code=204)
def register_device(body: DeviceRegister, user: CurrentUser, db: DbSession):
    """R3 · Register an FCM token; a known token moves to the current user."""
    device = db.scalar(select(Device).where(Device.fcm_token == body.fcm_token))
    if device is None:
        db.add(Device(user_id=user.id, fcm_token=body.fcm_token, platform=body.platform,
                      last_seen_at=now_utc()))
    else:
        device.user_id, device.platform, device.last_seen_at = user.id, body.platform, now_utc()
    db.flush()
    return Response(status_code=204)


@router.delete("/devices/{fcm_token}", status_code=204)
def unregister_device(fcm_token: str, user: CurrentUser, db: DbSession):
    """R4 · Unregister a device (call on logout); unknown tokens are fine."""
    device = db.scalar(select(Device).where(Device.fcm_token == fcm_token, Device.user_id == user.id))
    if device is not None:
        db.delete(device)
        db.flush()
    return Response(status_code=204)


@router.get("/quotes/random", response_model=Quote)
def get_random_quote(user: CurrentUser, db: DbSession, context: QuoteContext = "general"):
    """R5 · Motivation quote about the user's sleep debt and next deadline; never fails (built-in list fallback)."""
    debt_hours = None
    if user.health_profile is not None:  # no profile yet: quote without sleep debt instead of a 404
        debt_hours = biorhythm_service.debt_summary(db, user, user.health_profile, 7)["total_debt_minutes"] / 60
    todos, _ = TodoRepository(db).page(user.id, statuses=(TodoStatus.TODO, TodoStatus.IN_PROGRESS),
                                       due_after=now_utc(), limit=1)
    deadline = (f"{todos[0].title}, {todos[0].deadline_at.astimezone(user_tz(user)):%H:%M %d/%m}"
                if todos else None)
    return Quote(**llm_quote(context, debt_hours, deadline))
