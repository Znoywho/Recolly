from datetime import time

from pydantic import BaseModel, Field

from app.models.enums import DevicePlatform


class QuietHours(BaseModel):
    start: time
    end: time


class ReminderSettingsBase(BaseModel):
    bedtime_reminder_enabled: bool = True
    bedtime_reminder_minutes_before: int = Field(default=30, ge=0, le=240)
    deadline_reminder_enabled: bool = True
    deadline_reminder_hours_before: list[int] = Field(default_factory=lambda: [24, 2])
    motivation_enabled: bool = True
    quiet_hours: QuietHours | None = None


class ReminderSettingsUpdate(ReminderSettingsBase):
    pass


class ReminderSettingsRead(ReminderSettingsBase):
    pass


class DeviceRegister(BaseModel):
    fcm_token: str = Field(max_length=512)
    platform: DevicePlatform = DevicePlatform.ANDROID
