from fastapi import APIRouter, Response
from sqlalchemy import select

from app.core.deps import CurrentUser, DbSession
from app.core.timeutil import now_utc
from app.models.notification import Device, ReminderSettings as ReminderSettingsRow
from app.schemas.notification import DeviceRegister, Quote, QuoteContext, ReminderSettings
from app.schemas.schedule import ClockWindow
from app.service.quotes import random_quote

router = APIRouter(tags=["Reminders"])


def _settings(row: ReminderSettingsRow | None) -> ReminderSettings:
    if row is None:
        return ReminderSettings()
    quiet = None
    if row.quiet_hours_start is not None and row.quiet_hours_end is not None:
        quiet = ClockWindow(start=row.quiet_hours_start, end=row.quiet_hours_end)
    return ReminderSettings(
        bedtime_reminder_enabled=row.bedtime_reminder_enabled,
        bedtime_reminder_minutes_before=row.bedtime_reminder_minutes_before,
        deadline_reminder_enabled=row.deadline_reminder_enabled,
        deadline_reminder_hours_before=list(row.deadline_reminder_hours_before),
        kss_prompt_enabled=row.kss_prompt_enabled,
        kss_prompts_per_day=row.kss_prompts_per_day,
        kss_prompt_window=ClockWindow(start=row.kss_prompt_window_start, end=row.kss_prompt_window_end),
        sleep_confirm_enabled=row.sleep_confirm_enabled,
        motivation_enabled=row.motivation_enabled,
        quiet_hours=quiet,
    )


@router.get("/reminder-settings", response_model=ReminderSettings)
def get_reminder_settings(user: CurrentUser):
    """R1 · Reminder settings (defaults until the user saves them)."""
    return _settings(user.reminder_settings)


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
    return _settings(row)


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
def get_random_quote(user: CurrentUser, context: QuoteContext = "general"):
    """R5 · Motivation quote; never fails (built-in list until Gemini is plugged in)."""
    return Quote(**random_quote(context))
