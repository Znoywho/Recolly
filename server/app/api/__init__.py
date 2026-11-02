from fastapi import APIRouter

from app.api import (
    auth_api,
    biorhythm_api,
    calendar_api,
    event_api,
    health_profile_api,
    home_api,
    reminder_api,
    schedule_api,
    sleep_api,
    system_api,
    timetable_api,
    todo_api,
    user_api,
)

api_router = APIRouter(prefix="/api/v1")
for module in (auth_api, user_api, health_profile_api, sleep_api, biorhythm_api, timetable_api,
               event_api, todo_api, schedule_api, calendar_api, reminder_api, home_api, system_api):
    api_router.include_router(module.router)
