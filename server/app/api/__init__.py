from fastapi import APIRouter, Depends

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
    voice_api,
)
from app.core.rate_limit import rate_limit

# Every route: 120 requests/min per user (or per IP before login); expensive routes add their own limit.
api_router = APIRouter(prefix="/api/v1", dependencies=[Depends(rate_limit("all", limit=120))])
for module in (auth_api, user_api, health_profile_api, sleep_api, biorhythm_api, timetable_api,
               event_api, todo_api, schedule_api, calendar_api, reminder_api, home_api, voice_api, system_api):
    api_router.include_router(module.router)
