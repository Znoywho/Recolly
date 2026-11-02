from datetime import time
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.models.enums import DevicePlatform
from app.schemas.schedule import ClockWindow


class ReminderSettings(BaseModel):
    bedtime_reminder_enabled: bool = True
    bedtime_reminder_minutes_before: int = Field(
        default=30, ge=0, le=240, description="Before tonight's recommended_sleep_at (H8).")
    deadline_reminder_enabled: bool = True
    deadline_reminder_hours_before: list[int] = Field(default_factory=lambda: [24, 2], max_length=5)
    kss_prompt_enabled: bool = True
    kss_prompts_per_day: int = Field(default=4, ge=1, le=6)
    kss_prompt_window: ClockWindow = Field(
        default_factory=lambda: ClockWindow(start=time(8, 0), end=time(23, 0)))
    sleep_confirm_enabled: bool = True
    motivation_enabled: bool = True
    quiet_hours: ClockWindow | None = None

    @field_validator("deadline_reminder_hours_before")
    @classmethod
    def _hours(cls, value: list[int]) -> list[int]:
        if len(set(value)) != len(value):
            raise ValueError("hours must be unique")
        if any(not 1 <= h <= 168 for h in value):
            raise ValueError("each value must be within 1..168")
        return value


class DeviceRegister(BaseModel):
    fcm_token: str = Field(min_length=1, max_length=512)
    platform: DevicePlatform = DevicePlatform.ANDROID


QuoteContext = Literal["general", "deadline", "sleep", "progress"]


class Quote(BaseModel):
    text: str
    author: str | None
    source: Literal["gemini", "fallback"]
    context: QuoteContext
