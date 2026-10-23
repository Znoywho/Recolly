# Recolly API v1 — Draft

> Status: **DRAFT** — needs review by the whole team before freezing (R01).
> Owner: Backend (Member 1). Consumers: Flutter (Members 2, 3).

## 1. Conventions

| Item | Rule |
|---|---|
| Base URL | `https://<host>/api/v1` (local: `http://localhost:8765/api/v1`) |
| Format | JSON (`Content-Type: application/json`), except uploads (`multipart/form-data`) |
| Auth | `Authorization: Bearer <access_token>` on every endpoint unless marked **Public** |
| Datetime | ISO 8601 with offset, e.g. `2026-10-19T08:00:00+07:00`. Dates: `YYYY-MM-DD`. Times: `HH:MM` |
| Recurrence | RFC 5545 RRULE string, e.g. `FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231T000000Z` |
| IDs | UUID v4 strings |
| Field naming | `snake_case` |
| Pagination | Query `?limit=20&cursor=<opaque>` → response `{ "items": [...], "next_cursor": "..." \| null }` |
| Partial update | `PATCH` sends only the fields to change. An omitted field is unchanged; `null` on a nullable field clears it |

### Error format

```json
{ "detail": "Todo not found", "code": "TODO_NOT_FOUND" }
```

| HTTP | When |
|---|---|
| 400 | Bad request (invalid file, unsupported format) |
| 401 | Missing / expired / invalid token |
| 403 | Resource belongs to another user, or missing Google scope |
| 404 | Resource not found |
| 409 | Conflict (e.g. Google Calendar sync conflict) |
| 413 | Uploaded file too large |
| 422 | Validation error (FastAPI default body) |
| 503 | AI model / external service unavailable |

## 2. Shared enums

| Enum | Values |
|---|---|
| `chronotype` | `morning`, `intermediate`, `evening` |
| `event_source` | `manual`, `ocr`, `scheduler`, `google` |
| `sync_status` | `not_synced`, `pending`, `synced`, `conflict`, `error` |
| `todo_status` | `todo`, `in_progress`, `done` |
| `todo_category` | `study`, `assignment`, `exam`, `personal`, `other` |
| `priority` | `low`, `medium`, `high` |
| `job_status` | `queued`, `processing`, `succeeded`, `failed` |

## 3. Endpoint summary

| # | Method | Path | Description | Task |
|---|---|---|---|---|
| **Auth** |
| A1 | POST | `/auth/google` | Sign in with Google (Public) | R08 |
| A2 | POST | `/auth/refresh` | Get a new access token (Public) | R08 |
| A3 | POST | `/auth/logout` | Revoke refresh token | R08 |
| **User** |
| U1 | GET | `/users/me` | Current user | R61 |
| U2 | PATCH | `/users/me` | Update profile | R61 |
| U3 | DELETE | `/users/me` | Delete account + data | R61 |
| **Health & sleep** |
| H1 | GET | `/health-profile` | Get sleep profile | R55 |
| H2 | PUT | `/health-profile` | Create / replace sleep profile | R55 |
| H3 | GET | `/sleep-logs` | List sleep logs (`?from=&to=`) | R17 |
| H4 | POST | `/sleep-logs` | Add sleep log | R17 |
| H5 | PATCH | `/sleep-logs/{id}` | Edit sleep log | R17 |
| H6 | DELETE | `/sleep-logs/{id}` | Delete sleep log | R17 |
| H7 | GET | `/sleep-debt` | Sleep debt summary (`?days=7`) | R20, R35 |
| H8 | GET | `/biorhythm` | Process S/C alertness curve (`?date=`) | R20, R59 |
| **OCR & timetable** |
| T1 | POST | `/ocr/timetable` | Upload timetable photo → job | R09 |
| T2 | GET | `/ocr/jobs/{job_id}` | OCR job status + parsed result | R10, R11 |
| T3 | GET | `/timetable` | List subjects | R15 |
| T4 | POST | `/timetable` | Save subjects (bulk, from OCR or manual) | R15, R16 |
| T5 | PATCH | `/timetable/{id}` | Edit subject | R15 |
| T6 | DELETE | `/timetable/{id}` | Delete subject | R15 |
| **Events** |
| E1 | GET | `/events` | List events in range (`?from=&to=`, expands recurrence) | R28 |
| E2 | POST | `/events` | Create event | R28 |
| E3 | GET | `/events/{id}` | Event detail | R58 |
| E4 | PATCH | `/events/{id}` | Edit event | R58 |
| E5 | DELETE | `/events/{id}` | Delete event | R58 |
| **Todos** |
| D1 | GET | `/todos` | List (`?status=&category=&due_before=`) | R21 |
| D2 | POST | `/todos` | Create todo | R21 |
| D3 | GET | `/todos/{id}` | Todo detail | R21 |
| D4 | PATCH | `/todos/{id}` | Edit / change status | R21 |
| D5 | DELETE | `/todos/{id}` | Delete todo | R21 |
| **Voice** |
| V1 | POST | `/voice/transcribe` | Audio → transcript + todo draft | R42, R43 |
| **Scheduler** |
| S1 | POST | `/schedule/generate` | Run CP-SAT → suggested study blocks (not saved) | R24–R27 |
| S2 | POST | `/schedule/apply` | Save chosen suggestions as events | R27 |
| **Google Calendar** |
| G1 | GET | `/calendar/status` | Connection + last sync info | R32, R46 |
| G2 | POST | `/calendar/sync` | Push pending events to Google | R30 |
| G3 | GET | `/calendar/conflicts` | List sync conflicts | R45 |
| G4 | POST | `/calendar/conflicts/{id}/resolve` | Keep local or keep Google version | R45 |
| G5 | POST | `/calendar/webhook` | Google push notification (Public, verified by channel token) | R45 |
| **Reminders & motivation** |
| R1 | GET | `/reminder-settings` | Get reminder settings | R38, R39 |
| R2 | PUT | `/reminder-settings` | Update reminder settings | R38, R39 |
| R3 | POST | `/devices` | Register FCM token | R40 |
| R4 | DELETE | `/devices/{fcm_token}` | Unregister device | R40 |
| R5 | GET | `/quotes/random` | Motivation quote (Gemini, with fallback) | R49, R50 |
| **System** |
| X1 | GET | `/health` | Liveness check (Public) | R03 |

## 4. Endpoint details

### Auth

Login is **Google-only**. Flutter uses `google_sign_in` with `serverClientId` set, requests scopes
`openid email profile https://www.googleapis.com/auth/calendar.events`, and sends the `serverAuthCode`
to the backend. The backend exchanges it for Google tokens, stores the refresh token (encrypted), and
issues its own JWTs.

**A1 `POST /auth/google`** — Public

```json
// request
{ "server_auth_code": "4/0Ab..." }
// 200
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "expires_in": 900,
  "user": { "...": "see User object" },
  "is_new_user": true
}
```

`is_new_user = true` → Flutter shows onboarding / sleep profile (R55).

**A2 `POST /auth/refresh`** — Public

```json
// request
{ "refresh_token": "eyJ..." }
// 200
{ "access_token": "eyJ...", "refresh_token": "eyJ...", "token_type": "bearer", "expires_in": 900 }
```

Refresh tokens rotate: the old one is invalid after use.

**A3 `POST /auth/logout`** → `204`. Body: `{ "refresh_token": "eyJ..." }`.

### User

**User object**

```json
{
  "id": "uuid",
  "email": "student@gmail.com",
  "display_name": "Nguyen Van A",
  "avatar_url": "https://...",
  "date_of_birth": "2005-03-12",
  "timezone": "Asia/Ho_Chi_Minh",
  "google_calendar_connected": true,
  "created_at": "2026-10-19T08:00:00+07:00",
  "last_login_at": "2026-10-19T08:00:00+07:00"
}
```

**U2 `PATCH /users/me`** — editable: `display_name`, `date_of_birth`, `timezone`.

**U3 `DELETE /users/me`** → `204`.

### Health & sleep

**Health profile object** (H1 / H2)

```json
{
  "chronotype": "evening",
  "usual_sleep_time": "23:30",
  "usual_wake_time": "07:00",
  "sleep_need_hours": 8.0
}
```

H1 returns `404 HEALTH_PROFILE_NOT_FOUND` if onboarding is not finished.

**Sleep log object** (H3–H6)

```json
{
  "id": "uuid",
  "sleep_at": "2026-10-18T23:45:00+07:00",
  "wake_at": "2026-10-19T06:50:00+07:00",
  "duration_minutes": 425,
  "quality": 3,
  "note": null
}
```

`quality`: 1–5, optional. `duration_minutes` is computed by the server (read-only).

**H7 `GET /sleep-debt?days=7`**

```json
{
  "days": 7,
  "total_debt_minutes": 310,
  "daily": [
    { "date": "2026-10-13", "slept_minutes": 400, "need_minutes": 480, "debt_minutes": 80 }
  ]
}
```

**H8 `GET /biorhythm?date=2026-10-19`**

```json
{
  "date": "2026-10-19",
  "interval_minutes": 30,
  "points": [
    { "time": "2026-10-19T08:00:00+07:00", "process_s": 0.32, "process_c": 0.61, "alertness": 0.71 }
  ],
  "peak_windows": [
    { "start": "2026-10-19T09:30:00+07:00", "end": "2026-10-19T11:30:00+07:00" }
  ],
  "low_windows": [
    { "start": "2026-10-19T14:00:00+07:00", "end": "2026-10-19T15:00:00+07:00" }
  ]
}
```

`process_s`, `process_c`, `alertness` are normalized to 0–1.

### OCR & timetable

OCR runs asynchronously (Vintern is slow). Flutter uploads, then polls T2 every ~2s.

**T1 `POST /ocr/timetable`** — `multipart/form-data`, field `image` (jpg/png/heic, max 10 MB)

```json
// 202
{ "job_id": "uuid", "status": "queued" }
```

**T2 `GET /ocr/jobs/{job_id}`**

```json
{
  "job_id": "uuid",
  "status": "succeeded",
  "error": null,
  "result": {
    "subjects": [
      {
        "name": "Cấu trúc dữ liệu",
        "code": "IT003",
        "room": "B1.02",
        "lecturer": "Nguyen Van B",
        "day_of_week": 1,
        "start_time": "07:30",
        "end_time": "09:45",
        "start_date": "2026-09-07",
        "end_date": "2026-12-20",
        "confidence": 0.87
      }
    ]
  }
}
```

`day_of_week`: 1 = Monday … 7 = Sunday. If `status = failed`, `error` holds a code like `OCR_NO_TABLE_FOUND` (Flutter shows the scan-failed screen, R62). Jobs are kept for 24 h, then T2 returns `404 OCR_JOB_NOT_FOUND`.

**Subject object** (T3–T6): same fields as an OCR subject without `confidence`, plus `id` and `color` (hex, optional).

**T4 `POST /timetable`** — bulk save after the user edits the OCR result

```json
// request
{ "subjects": [ { "name": "...", "day_of_week": 1, "start_time": "07:30", "...": "..." } ], "replace_existing": false }
// 201
{ "items": [ { "id": "uuid", "...": "..." } ] }
```

Saving subjects also creates recurring events (`source = "ocr"` or `"manual"`) so they appear in E1.

### Events

**Event object**

```json
{
  "id": "uuid",
  "title": "Ôn thi Giải tích",
  "description": null,
  "location": null,
  "start_at": "2026-10-20T09:30:00+07:00",
  "end_at": "2026-10-20T11:00:00+07:00",
  "all_day": false,
  "rrule": null,
  "source": "scheduler",
  "subject_id": null,
  "todo_id": "uuid",
  "google_event_id": "abc123",
  "sync_status": "synced",
  "created_at": "...",
  "updated_at": "..."
}
```

- **E1 `GET /events?from=&to=`**: `from` and `to` are required, max range 62 days. Recurring events are expanded into instances, and each instance has `id` plus `occurrence_start`.
- E2 / E4 writable fields: `title`, `description`, `location`, `start_at`, `end_at`, `all_day`, `rrule`, `todo_id`.
- If an edited event was already synced, `sync_status` becomes `pending`.

### Todos

**Todo object**

```json
{
  "id": "uuid",
  "title": "Bài tập lớn CTDL",
  "description": "Chương 3–5",
  "category": "assignment",
  "status": "todo",
  "priority": "high",
  "deadline_at": "2026-10-25T23:59:00+07:00",
  "estimated_minutes": 240,
  "difficulty": 4,
  "start_at": null,
  "end_at": null,
  "created_at": "...",
  "updated_at": "..."
}
```

- `difficulty` is 1–5. The scheduler puts hard tasks in peak alertness windows.
- `estimated_minutes` + `deadline_at` are required for a todo to be scheduled by S1.
- `start_at` / `end_at` are optional, for todos with a fixed time.

### Voice

**V1 `POST /voice/transcribe`** — `multipart/form-data`, field `audio` (m4a/wav/ogg, max 25 MB, max 60s)

```json
// 200
{
  "transcript": "Thứ sáu nộp bài tập lớn cấu trúc dữ liệu",
  "todo_draft": {
    "title": "Nộp bài tập lớn cấu trúc dữ liệu",
    "category": "assignment",
    "deadline_at": "2026-10-23T23:59:00+07:00",
    "estimated_minutes": null,
    "priority": "medium"
  }
}
```

The draft is **not saved**. Flutter lets the user edit it, then calls D2.

### Scheduler

**S1 `POST /schedule/generate`**

```json
// request
{
  "from": "2026-10-20",
  "to": "2026-10-26",
  "todo_ids": null,
  "options": { "max_study_minutes_per_day": 240, "block_minutes": 50, "break_minutes": 10 }
}
// 200
{
  "suggestion_id": "uuid",
  "blocks": [
    {
      "todo_id": "uuid",
      "title": "Bài tập lớn CTDL",
      "start_at": "2026-10-21T09:30:00+07:00",
      "end_at": "2026-10-21T10:20:00+07:00",
      "alertness": 0.82
    }
  ],
  "unscheduled": [ { "todo_id": "uuid", "reason": "NOT_ENOUGH_TIME_BEFORE_DEADLINE" } ],
  "solver_status": "OPTIMAL"
}
```

`todo_ids = null` → all todos that are not `done`. Suggestions expire after 1 hour.

**S2 `POST /schedule/apply`**

```json
// request
{ "suggestion_id": "uuid", "block_indexes": null, "sync_to_google": true }
// 201
{ "events": [ { "...": "Event object" } ] }
```

`block_indexes = null` → apply all blocks.

### Google Calendar

**G1 `GET /calendar/status`**

```json
{
  "connected": true,
  "calendar_id": "primary",
  "two_way_sync": true,
  "last_synced_at": "2026-10-19T08:00:00+07:00",
  "pending_count": 2,
  "conflict_count": 0
}
```

**G2 `POST /calendar/sync`** → `200 { "pushed": 5, "failed": 0, "conflicts": 0 }`.
Returns `403 GOOGLE_SCOPE_MISSING` if the user did not grant the Calendar scope.

**G3 `GET /calendar/conflicts`**

```json
{
  "items": [
    {
      "id": "uuid",
      "event_id": "uuid",
      "local": { "...": "Event object" },
      "google": { "title": "...", "start_at": "...", "end_at": "..." },
      "detected_at": "..."
    }
  ]
}
```

**G4 `POST /calendar/conflicts/{id}/resolve`** — body `{ "keep": "local" | "google" }` → `200` Event object.

**G5 `POST /calendar/webhook`** — called by Google, not by Flutter. Verified with the
`X-Goog-Channel-Token` header. Always returns `200` quickly and processes the change in the background.

### Reminders & motivation

**Reminder settings object** (R1 / R2)

```json
{
  "bedtime_reminder_enabled": true,
  "bedtime_reminder_minutes_before": 30,
  "deadline_reminder_enabled": true,
  "deadline_reminder_hours_before": [24, 2],
  "motivation_enabled": true,
  "quiet_hours": { "start": "23:00", "end": "07:00" }
}
```

**R3 `POST /devices`** — body `{ "fcm_token": "...", "platform": "android" }` → `204`.

**R5 `GET /quotes/random?context=deadline`** — `context`: `general | deadline | sleep | progress`

```json
{ "text": "...", "author": null, "source": "gemini" }
```

`source` is `"gemini"` or `"fallback"`.

### System

**X1 `GET /health`** → `200 { "status": "ok", "db": "ok", "redis": "ok" }`.
