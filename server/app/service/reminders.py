"""Reminder rules (R39): which push notifications fall due in a time window.

A reminder is due when its trigger time is in [window_start, window_end):
- bedtime: tonight's recommended_sleep_at − bedtime_reminder_minutes_before
- deadline: deadline_at − h, for each h in deadline_reminder_hours_before (open todos only)
Triggers inside quiet hours are dropped. Payloads follow the contract's PushPayload.
"""

from datetime import datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.enums import TodoStatus
from app.models.notification import ReminderSettings as ReminderSettingsRow
from app.models.todo import Todo
from app.models.user import User
from app.schemas.notification import ReminderSettings
from app.schemas.schedule import ClockWindow
from app.service import biorhythm_service


def reminder_settings_of(row: ReminderSettingsRow | None) -> ReminderSettings:
    """The user's saved settings as the API schema (defaults until the user saves them)."""
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


def in_clock_window(moment: time, window: ClockWindow) -> bool:
    """start ≤ moment < end, where a window with end < start crosses midnight."""
    if window.start <= window.end:
        return window.start <= moment < window.end
    return moment >= window.start or moment < window.end


def bedtime_reminders(db: Session, user: User, settings: ReminderSettings,
                      window_start: datetime, window_end: datetime) -> list[dict[str, Any]]:
    """Bedtime reminder if recommended_sleep_at − minutes_before falls in the window."""
    if not settings.bedtime_reminder_enabled or user.health_profile is None:
        return []
    tz = ZoneInfo(user.timezone)
    today = window_end.astimezone(tz).date()
    # Last night too: a bedtime after midnight belongs to the previous day's night.
    timeline = biorhythm_service.timeline_for(db, user, user.health_profile, today - timedelta(days=1), 2)
    before = timedelta(minutes=settings.bedtime_reminder_minutes_before)
    due = []
    for night_of in (today - timedelta(days=1), today):
        bedtime = timeline.night(night_of).recommended_sleep_at
        if window_start <= bedtime - before < window_end:
            due.append({"type": "bedtime", "title": "Sắp tới giờ ngủ",
                        "body": f"Đi ngủ lúc {bedtime.astimezone(tz):%H:%M} để mai tỉnh táo nhé.",
                        "deep_link": "recolly://sleep", "scheduled_for": bedtime.isoformat(),
                        "trigger_at": bedtime - before})
    return due


def deadline_reminders(db: Session, user: User, settings: ReminderSettings,
                       window_start: datetime, window_end: datetime) -> list[dict[str, Any]]:
    """One reminder per open todo and per `h` whose deadline_at − h falls in the window."""
    if not settings.deadline_reminder_enabled or not settings.deadline_reminder_hours_before:
        return []
    furthest = timedelta(hours=max(settings.deadline_reminder_hours_before))
    todos = db.scalars(select(Todo).where(
        Todo.user_id == user.id, Todo.status != TodoStatus.DONE,
        Todo.deadline_at >= window_start, Todo.deadline_at < window_end + furthest)).all()
    due = []
    for todo in todos:
        for hours in settings.deadline_reminder_hours_before:
            trigger = todo.deadline_at - timedelta(hours=hours)
            if window_start <= trigger < window_end:
                due.append({"type": "deadline", "title": f"Còn {hours} giờ: {todo.title}",
                            "body": "Mở Recolly để xem lịch học cho việc này.",
                            "deep_link": f"recolly://todos/{todo.id}", "ref_id": str(todo.id),
                            "scheduled_for": todo.deadline_at.isoformat(), "trigger_at": trigger})
    return due


def due_reminders(db: Session, user: User, window_start: datetime, window_end: datetime) -> list[dict[str, Any]]:
    """Every PushPayload due for `user` in [window_start, window_end), quiet hours removed."""
    settings = reminder_settings_of(user.reminder_settings)
    due = (bedtime_reminders(db, user, settings, window_start, window_end)
           + deadline_reminders(db, user, settings, window_start, window_end))
    tz = ZoneInfo(user.timezone)
    quiet = settings.quiet_hours
    return [{k: v for k, v in p.items() if k != "trigger_at"} for p in due
            if quiet is None or not in_clock_window(p["trigger_at"].astimezone(tz).time(), quiet)]
