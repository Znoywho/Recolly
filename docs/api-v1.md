# Recolly API v1 — Draft 2

> Status: **DRAFT** — needs review by the whole team before freezing (R01).
> Owner: Backend (Member 1). Consumers: Flutter (Members 2, 3).
>
> **Source of truth: [`openapi.yaml`](openapi.yaml)** (OpenAPI 3.1, every field, type and error code).
> This page is the overview. Preview it with `npx @redocly/cli preview-docs docs/openapi.yaml`
> or paste it into <https://editor.swagger.io>. Changes since draft 1: see [§5](#5-changes-since-draft-1).

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
| 410 | Expired resource (scheduler suggestion older than 1 h) |
| 413 | Uploaded file too large |
| 422 | Validation error (FastAPI default body) |
| 429 | Too many AI requests (OCR, voice, Gemini) |
| 503 | AI model / external service unavailable |

Full list of `code` values: `info.description` in `openapi.yaml`.

## 2. Shared enums

| Enum | Values |
|---|---|
| `chronotype` | `lion`, `bear`, `wolf` (shown as animals; MSFsc < 04:00 / 04:00–06:00 / ≥ 06:00) |
| `chronotype_spectrum` | `early`, `slightly_early`, `intermediate`, `slightly_late`, `late` |
| `sleep_concern` | `none`, `watch`, `dolphin` (fragmented-sleep flag, not a chronotype) |
| `event_source` | `manual`, `ocr`, `scheduler`, `google` |
| `sync_status` | `not_synced`, `pending`, `synced`, `conflict`, `error` |
| `todo_status` | `todo`, `in_progress`, `done` |
| `todo_category` | `study`, `assignment`, `exam`, `personal`, `other` |
| `priority` | `low`, `medium`, `high` |
| `job_status` | `queued`, `processing`, `succeeded`, `failed` |
| `event_kind` | `class`, `study`, `rest`, `bedtime`, `other` |
| `chronotype_source` | `mctq`, `rmeq`, `self_report` |
| `sleep_source` | `manual`, `screen_inferred` |
| `prior_source` | `population`, `questionnaire` |
| `personalization_level` | `prior_only` (0 KSS days), `early` (1–3), `developing` (4–13), `personalized` (≥ 14) |

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
| **Chronotype & health** |
| C1 | POST | `/chronotype/assess` | **New.** Score questionnaire → animal + dolphin flag + typical-week energy curve (not saved) | R18, R55 |
| H1 | GET | `/health-profile` | Get sleep profile | R55 |
| H2 | PUT | `/health-profile` | Create / replace sleep profile (+ MCTQ, rMEQ, screen consent) | R55 |
| H3 | GET | `/sleep-logs` | List sleep logs (`?from=&to=&source=&confirmed=`) | R17 |
| H4 | POST | `/sleep-logs` | Add sleep log | R17 |
| H5 | PATCH | `/sleep-logs/{id}` | Edit sleep log | R17 |
| H6 | DELETE | `/sleep-logs/{id}` | Delete sleep log | R17 |
| H9 | POST | `/sleep-logs/{id}/confirm` | **New.** *(later)* One-tap confirm of an inferred sleep log | R17, R34 |
| H7 | GET | `/sleep-debt` | Sleep debt + social jetlag (`?days=7`) | R20, R35 |
| **Screen → sleep inference** (Android) |
| P1 | POST | `/screen-events` | **New.** *(later)* Upload screen on/off events (UsageStatsManager) | R17, R19 |
| P2 | GET | `/screen-events/summary` | **New.** *(later)* Screen data coverage | R17 |
| P3 | DELETE | `/screen-events` | **New.** *(later)* Delete all raw screen data (privacy) | R17 |
| P4 | POST | `/sleep-inference` | **New.** *(later)* Run the HMM now → inferred sleep logs | R19 |
| **KSS check-ins** |
| K1 | GET | `/kss-checkins` | **New.** *(later)* List sleepiness check-ins | R19, R59 |
| K2 | POST | `/kss-checkins` | **New.** *(later)* Record KSS 1–9 → Bayes update | R19, R59 |
| K3 | DELETE | `/kss-checkins/{id}` | **New.** *(later)* Delete a check-in | R19 |
| **Biorhythm** |
| H8 | GET | `/biorhythm` | Process S/C, predicted KSS, golden hours, projected sleep (`?date=&days=&interval_minutes=`) | R18, R20, R59 |
| B1 | GET | `/biorhythm/model` | **New.** *(later)* Personal parameters (φ, χw) + learning progress | R18, R19, R59 |
| B2 | POST | `/biorhythm/model/reset` | **New.** *(later)* Reset personalisation to a prior | R19 |
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
| G6 | POST | `/calendar/connection` | **New.** Connect / re-grant Calendar scope | R30, R32 |
| G7 | DELETE | `/calendar/connection` | **New.** Disconnect Google Calendar | R32 |
| G8 | PATCH | `/calendar/settings` | **New.** Change `calendar_id` / `two_way_sync` | R32, R46 |
| G2 | POST | `/calendar/sync` | Push pending events (and pull when two-way) | R30, R31 |
| G3 | GET | `/calendar/conflicts` | List sync conflicts | R45 |
| G4 | POST | `/calendar/conflicts/{id}/resolve` | Keep local or keep Google version | R45 |
| G5 | POST | `/calendar/webhook` | Google push notification (Public, verified by channel token) | R45 |
| **Reminders & motivation** |
| R1 | GET | `/reminder-settings` | Get reminder settings | R38, R39 |
| R2 | PUT | `/reminder-settings` | Update reminder settings | R38, R39 |
| R3 | POST | `/devices` | Register FCM token | R40 |
| R4 | DELETE | `/devices/{fcm_token}` | Unregister device | R40 |
| R5 | GET | `/quotes/random` | Motivation quote (Gemini, with fallback) | R49, R50 |
| **Home** |
| O1 | GET | `/home` | **New.** Everything the Home screen needs in one call | R56, R60 |
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
  "onboarding_completed": true,
  "created_at": "2026-10-19T08:00:00+07:00",
  "last_login_at": "2026-10-19T08:00:00+07:00"
}
```

`onboarding_completed = false` → the splash screen routes to onboarding even when `is_new_user` was `false`.

**U2 `PATCH /users/me`** — editable: `display_name`, `date_of_birth`, `timezone`.

**U3 `DELETE /users/me`** → `204`.

### Sleep model (how Module 2 works)

Based on the Recolly sleep research (personalised two-process model).

**Course project (draft 2.1):** only the questionnaire path ships. Endpoints marked *(later)* stay in
the contract for after the course project.

```
questionnaire ─► MSFsc ─┬─► lion / bear / wolf + dolphin flag ──────────────► C1 result card
                        └─► φ ─┐
school / free-day sleep times ─┴─► 2PM on a typical week ─► predicted KSS ─► H8 ─► CP-SAT ─► Google Calendar
```

Full design (after the course project):

```
screen on/off ──► HMM ──► sleep/wake ──┐
MCTQ / rMEQ ────► chronotype prior ────┼─► 2PM + Bayes ──► predicted KSS ──► CP-SAT ──► Google Calendar
KSS check-ins ─────────────────────────┘     ▲ updated on every check-in
```

- **Process S** = sleep pressure `H` (0–1). **Process C** = `cos(2π(t − φ)/24)`; the phase `φ` **is** the chronotype.
- **Alertness** `A = H⁺(t) − H(t)` (distance to the sleep threshold; `A ≤ 0` = should be asleep).
  **KSS** (1 very alert … 9 fighting sleep) `= 7.5 − 9·A`. UI number: `alertness_score = 100·(9 − kss_pred)/8`.
- Each user has a posterior over `(φ, χw)`, starting from a prior (population, or MCTQ + 0.9 h bias
  correction) and sharpened by every KSS check-in. After ~14 days of check-ins it is near its floor.

### Chronotype & health

**Onboarding flow (R55):** questionnaire → **C1** shows the result card
("you are a Bear 🐻, natural sleep 01:45–08:24", energy curve, what-if slider) → user confirms → **H2** saves it.

**C1 `POST /chronotype/assess`** — body `{ "mctq": {...}, "rmeq_score": 14, "regular_schedule": true,
"sleep_quality": {...}, "school_onset_shift_minutes": 0 }` (`mctq` or `rmeq_score` required)

- Animal from MSFsc: `< 04:00` lion, `04:00–06:00` bear, `≥ 06:00` wolf; from rMEQ only: `≥ 18` / `12–17` / `≤ 11`.
- `regular_schedule = false` or `work_days = 7` → MCTQ is skipped and `rmeq_score` is required (`422 RMEQ_REQUIRED`).
- `sleep_concern = dolphin` when F1 or F2 is `3+` nights a week for `>3m`; it never changes the animal.
- `typical_week`: the 2PM on the questionnaire sleep times — 7 day summaries + a 15-min energy curve.
  `school_onset_shift_minutes` drives the what-if slider (φ unchanged).

```json
// request
{ "mctq": { "sleep_onset_work": "00:30", "sleep_end_work": "06:30",
            "sleep_onset_free": "01:45", "sleep_end_free": "10:00", "work_days": 5,
            "alarm_on_free_days": false },
  "sleep_quality": { "slow_onset_nights": "1-2", "night_waking_nights": "0", "duration": null } }
// 200
{
  "chronotype": "bear",
  "spectrum": "intermediate",
  "sleep_concern": "none",
  "source": "mctq",
  "mctq_result": { "sd_work_hours": 6.0, "sd_free_hours": 8.25, "sd_week_hours": 6.64,
                   "msw": "03:30", "msf": "05:52", "msf_sc": "05:04",
                   "oversleep_corrected": true, "social_jetlag_hours": 2.38, "chronotype": "bear" },
  "rmeq_category": null,
  "phi_prior_hours": 18.39,
  "phi_prior_sd_hours": 1.0,
  "natural_sleep_time": "01:45",
  "natural_wake_time": "08:24",
  "sleep_shortfall_hours": 0.36,
  "typical_week": {
    "phi_hours": 18.39,
    "school_onset_shift_minutes": 0,
    "days": [ { "day": 0, "wake_time": "06:30", "sleep_time": "00:30", "kss_08": 4.3, "kss_14": 4.9,
                "kss_22": 6.5, "worst_time": "00:25", "worst_kss": 7.6, "minutes_past_threshold": 15,
                "peak_start": "07:00", "peak_mean_kss": 4.2 } ],
    "points": [ { "day": 0, "time": "09:00", "asleep": false, "alertness": 0.33, "kss": 4.6 } ]
  }
}
```

**Health profile object** (H1 / H2)

```json
{
  "chronotype": "bear",
  "spectrum": "intermediate",
  "sleep_concern": "none",
  "chronotype_source": "mctq",
  "usual_sleep_time": "23:30",
  "usual_wake_time": "07:00",
  "sleep_need_hours": 8.0,
  "morning_prep_minutes": 60,
  "mctq": { "...": "MCTQ answers or null" },
  "mctq_result": { "...": "computed, read-only" },
  "rmeq_score": null,
  "rmeq_category": null,
  "regular_schedule": true,
  "sleep_quality": { "...": "SleepQualityAnswers or null" },
  "screen_tracking_enabled": true,
  "updated_at": "..."
}
```

- H2 writable: `chronotype` (used only without questionnaire), `usual_sleep_time`, `usual_wake_time`,
  `sleep_need_hours`, `morning_prep_minutes`, `mctq`, `rmeq_score`, `regular_schedule`, `sleep_quality`,
  `screen_tracking_enabled`.
- H1 returns `404 HEALTH_PROFILE_NOT_FOUND` if onboarding is not finished.

**Sleep log object** (H3–H6, H9)

```json
{
  "id": "uuid",
  "sleep_at": "2026-10-18T23:45:00+07:00",
  "wake_at": "2026-10-19T06:50:00+07:00",
  "duration_minutes": 425,
  "quality": null,
  "note": null,
  "source": "screen_inferred",
  "confirmed": false,
  "confidence": 0.93,
  "created_at": "...",
  "updated_at": "..."
}
```

- `source = manual` logs are always `confirmed`. Inferred logs become confirmed via **H9** (1 tap) or **H5** (edit).
- Confirmed logs are never overwritten by inference; deleting an inferred log stops it from being recreated.
- `409 SLEEP_LOG_OVERLAP` if a log overlaps another confirmed log.

**H7 `GET /sleep-debt?days=7`**

```json
{
  "days": 7,
  "total_debt_minutes": 310,
  "average_sleep_minutes": 436,
  "social_jetlag_hours": 1.9,
  "current_process_s": 0.52,
  "daily": [
    { "date": "2026-10-13", "has_data": true, "slept_minutes": 400, "need_minutes": 480,
      "debt_minutes": 80, "mid_sleep": "03:10", "is_free_day": false }
  ]
}
```

`debt_minutes` can be negative (extra sleep pays back debt); `total_debt_minutes = max(0, Σ)`.

### Screen → sleep inference (Android)

Requires `screen_tracking_enabled = true` (else `403 SCREEN_TRACKING_DISABLED`) and the
`PACKAGE_USAGE_STATS` permission. Flutter reads `UsageStatsManager.queryEvents`
(`SCREEN_INTERACTIVE` → `on`, `SCREEN_NON_INTERACTIVE` → `off`) e.g. every morning and uploads:

**P1 `POST /screen-events`** → `202 { "accepted": 812, "duplicates": 0, "inference_queued": true }`

```json
{
  "window_start": "2026-10-18T07:00:00+07:00",
  "window_end": "2026-10-19T07:05:00+07:00",
  "events": [ { "type": "on", "at": "2026-10-18T23:31:10+07:00" }, { "type": "off", "at": "2026-10-18T23:44:52+07:00" } ]
}
```

The window matters: no events inside it = screen off; outside every window = no data. The server then
runs the HMM in the background and creates **unconfirmed** sleep logs → morning push `sleep_confirm`
→ Flutter shows "You slept 23:45–06:50 — correct?" → **H9** or **H5**.
**P4 `POST /sleep-inference`** runs it synchronously (`{ "from": "2026-10-12", "to": "2026-10-18" }`).

### KSS check-ins

Push `kss_prompt` arrives `kss_prompts_per_day` times (default 4) between 08:00 and 23:00.

**K2 `POST /kss-checkins`** — body `{ "score": 6, "trigger": "prompt" }` (`recorded_at` defaults to now)

```json
// 201
{
  "checkin": { "id": "uuid", "score": 6, "recorded_at": "...", "trigger": "prompt",
               "predicted_kss": 4.3, "used_by_model": true, "created_at": "..." },
  "model": { "phi_hours": 18.5, "phi_sd_hours": 0.43, "chi_w_hours": 18.9, "chi_w_sd_hours": 0.8,
             "personalization_level": "personalized", "kss_days": 14 }
}
```

`predicted_kss` is the model's guess **before** this answer ("model expected 4.3, you said 6").

### Biorhythm

**H8 `GET /biorhythm?date=2026-10-22&days=1&interval_minutes=15`** (abridged)

```json
{
  "date": "2026-10-22",
  "days": 1,
  "interval_minutes": 15,
  "timezone": "Asia/Ho_Chi_Minh",
  "model": { "phi_hours": 18.5, "personalization_level": "personalized", "...": "ModelSummary" },
  "points": [
    { "time": "2026-10-22T19:00:00+07:00", "asleep": false, "sleep_state": "projected",
      "process_s": 0.47, "process_c": 0.99, "upper_threshold": 0.79, "lower_threshold": 0.29,
      "alertness": 0.32, "kss_pred": 4.65, "kss_lo": 3.15, "kss_hi": 6.15, "alertness_score": 54 }
  ],
  "peak_windows": [
    { "start": "2026-10-22T09:30:00+07:00", "end": "2026-10-22T13:10:00+07:00",
      "mean_kss_pred": 3.65, "alertness_score": 67 }
  ],
  "low_windows": [ { "...": "same shape" } ],
  "projected_sleep": [
    { "night_of": "2026-10-22",
      "natural_sleep_at": "2026-10-23T02:07:00+07:00", "natural_wake_at": "2026-10-23T10:04:00+07:00",
      "required_wake_at": "2026-10-23T06:00:00+07:00", "recommended_sleep_at": "2026-10-22T22:00:00+07:00",
      "projected_sleep_minutes": 480 }
  ],
  "warnings": []
}
```

- Values are **raw model values**, not normalised: `process_s` 0–1, `process_c` −1…1, `alertness` may be < 0.
  Use `alertness_score` (0–100) for the UI; `kss_*` and `alertness_score` are `null` while asleep.
- `peak_windows` = golden hours (lowest 25 % predicted KSS of the day, ≥ 30 min, not in the first 30 min after waking).
- `recommended_sleep_at = min(natural_sleep_at, required_wake_at − sleep_need_hours)`; it drives the bedtime reminder.
- No sleep logs yet (the course-project default): sleep follows the questionnaire typical week,
  `sleep_state = typical`, warning `TYPICAL_WEEK`.
- `warnings`: `TYPICAL_WEEK`, `NO_RECENT_SLEEP_DATA`, `UNCONFIRMED_SLEEP_DATA`, `PRIOR_ONLY` — show a hint, still render the chart.

**B1 `GET /biorhythm/model`** — `estimate` (ModelSummary), `prior`, fixed `constants`, `kss_mapping`,
data counts, `reset_at`. For the Biorhythm screen's personalisation-progress card.
**B2 `POST /biorhythm/model/reset`** — body `{ "prior_source": "questionnaire" }` after a new semester.

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

**Subject object** (T3–T6): same fields as an OCR subject without `confidence`, plus `id`, `color` (hex, optional), `created_at`, `updated_at`.

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
  "start_at": "2026-10-20T19:00:00+07:00",
  "end_at": "2026-10-20T20:30:00+07:00",
  "all_day": false,
  "rrule": null,
  "kind": "study",
  "source": "scheduler",
  "subject_id": null,
  "todo_id": "uuid",
  "google_event_id": "abc123",
  "sync_status": "synced",
  "occurrence_start": null,
  "created_at": "...",
  "updated_at": "..."
}
```

- **E1 `GET /events?from=&to=&kind=&source=`**: `from` and `to` (date-time) are required, max range 62 days. Recurring events are expanded into instances, and each instance has the series `id` plus `occurrence_start`. Edits and deletes act on the whole series.
- E2 / E4 writable fields: `title`, `description`, `location`, `start_at`, `end_at`, `all_day`, `rrule`, `kind`, `todo_id`.
- `kind` (for calendar colours): `class` (from the timetable), `study` / `rest` / `bedtime` (from the scheduler), `other`.
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
  "scheduled_minutes": 90,
  "completed_at": null,
  "created_at": "...",
  "updated_at": "..."
}
```

- **D1 `GET /todos?status=todo&status=in_progress&category=&due_before=&due_after=&sort=deadline_at&limit=20&cursor=`** → `{ "items": [...], "next_cursor": null }`.
- `difficulty` is 1–5. The scheduler puts hard tasks in the lowest predicted-KSS slots (golden hours).
- `scheduled_minutes` (read-only) = minutes of study events already linked to the todo → progress bar vs `estimated_minutes`.
- `status = done` sets `completed_at`.
- `estimated_minutes` + `deadline_at` are required for a todo to be scheduled by S1.
- `start_at` / `end_at` are optional, for todos with a fixed time.

### Voice

**V1 `POST /voice/transcribe`** — `multipart/form-data`, field `audio` (m4a/wav/ogg, max 25 MB, max 60s),
optional field `reference_time` (device "now", to resolve "thứ sáu", "tối mai")

```json
// 200
{
  "transcript": "Thứ sáu nộp bài tập lớn cấu trúc dữ liệu",
  "todo_draft": {
    "title": "Nộp bài tập lớn cấu trúc dữ liệu",
    "description": null,
    "category": "assignment",
    "priority": "medium",
    "deadline_at": "2026-10-23T23:59:00+07:00",
    "estimated_minutes": null,
    "difficulty": null
  },
  "parser": "gemini"
}
```

`parser` is `gemini` or `rules` (fallback when Gemini is down).

The draft is **not saved**. Flutter lets the user edit it, then calls D2.

### Scheduler

**S1 `POST /schedule/generate`**

```json
// request (every option is optional; these are the defaults, from the research setup)
{
  "from": "2026-10-22",
  "to": "2026-10-25",
  "todo_ids": null,
  "options": {
    "max_study_minutes_per_day": 240,
    "block_minutes": 90,
    "min_block_minutes": 45,
    "min_break_minutes": 30,
    "wake_buffer_minutes": 30,
    "bed_buffer_minutes": 60,
    "meal_windows": [ { "start": "11:30", "end": "13:00" }, { "start": "18:00", "end": "19:00" } ],
    "include_rest_blocks": false,
    "include_bedtime_blocks": true
  }
}
// 200
{
  "suggestion_id": "uuid",
  "expires_at": "2026-10-22T10:00:00+07:00",
  "from": "2026-10-22",
  "to": "2026-10-25",
  "solver_status": "OPTIMAL",
  "blocks": [
    {
      "index": 0,
      "kind": "study",
      "todo_id": "uuid",
      "title": "Bài tập lớn CTDL",
      "start_at": "2026-10-24T09:30:00+07:00",
      "end_at": "2026-10-24T11:00:00+07:00",
      "predicted_kss": 3.6,
      "alertness_score": 68
    }
  ],
  "unscheduled": [ { "todo_id": "uuid", "reason": "NOT_ENOUGH_TIME_BEFORE_DEADLINE", "missing_minutes": 60 } ],
  "stats": { "study_minutes": 90, "mean_predicted_kss": 3.6, "golden_hour_ratio": 1.0, "solve_ms": 140 },
  "model": { "...": "ModelSummary" }
}
```

- **Hard constraints:** no overlap with events or projected sleep; nothing in the first `wake_buffer_minutes`
  after waking (sleep inertia) or the last `bed_buffer_minutes` before bedtime; meal windows free; blocks end
  before the deadline; ≥ `min_break_minutes` between blocks; ≤ `max_study_minutes_per_day`.
- **Objective:** minimise Σ predicted KSS × minutes, weighted by `difficulty`, + penalty for unscheduled minutes
  (weighted by priority). Same timetable → different plans for a morning vs an evening type.
- `kind`: `study`, `rest` (only with `include_rest_blocks`), `bedtime` (at `recommended_sleep_at`).
- `todo_ids = null` → all todos that are not `done`. Max range 14 days. Suggestions expire after 1 hour.

**S2 `POST /schedule/apply`**

```json
// request
{ "suggestion_id": "uuid", "block_indexes": null, "sync_to_google": true }
// 201
{ "events": [ { "...": "Event object" } ], "sync": { "pushed": 3, "pulled": 0, "failed": 0, "conflicts": 0 } }
```

`block_indexes = null` → apply all blocks. `sync` is `null` when `sync_to_google = false`.
`410 SUGGESTION_EXPIRED` after 1 hour.

### Google Calendar

**G1 `GET /calendar/status`**

```json
{
  "connected": true,
  "google_email": "student@gmail.com",
  "calendar_id": "primary",
  "two_way_sync": true,
  "last_synced_at": "2026-10-19T08:00:00+07:00",
  "pending_count": 2,
  "conflict_count": 0
}
```

**G6 `POST /calendar/connection`** — body `{ "server_auth_code": "..." }` (re-requested with the
`calendar.events` scope) → `200` status object. **G7 `DELETE /calendar/connection`** → `204`.
**G8 `PATCH /calendar/settings`** — body `{ "calendar_id": "primary", "two_way_sync": true }` → `200` status object.

**G2 `POST /calendar/sync`** — optional body `{ "event_ids": null }` → `200 { "pushed": 5, "pulled": 1, "failed": 0, "conflicts": 0 }`.
Returns `403 GOOGLE_SCOPE_MISSING` if the user did not grant the Calendar scope, `409 CALENDAR_NOT_CONNECTED` if not connected.

**G3 `GET /calendar/conflicts`**

```json
{
  "items": [
    {
      "id": "uuid",
      "event_id": "uuid",
      "local": { "...": "Event object" },
      "google": { "title": "...", "description": null, "location": null, "start_at": "...", "end_at": "...", "updated_at": "..." },
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
  "kss_prompt_enabled": true,
  "kss_prompts_per_day": 4,
  "kss_prompt_window": { "start": "08:00", "end": "23:00" },
  "sleep_confirm_enabled": true,
  "motivation_enabled": true,
  "quiet_hours": { "start": "23:00", "end": "07:00" }
}
```

The bedtime reminder fires `bedtime_reminder_minutes_before` before tonight's `recommended_sleep_at` (H8).
R1 returns the defaults above if the user never saved settings.

**R3 `POST /devices`** — body `{ "fcm_token": "...", "platform": "android" }` → `204`.

**Push payload (FCM `data`)** — documented under `webhooks.pushNotification` in `openapi.yaml`:

```json
{ "type": "kss_prompt", "title": "Bạn đang thấy thế nào?", "body": "Chạm để chấm độ buồn ngủ 1–9", "deep_link": "recolly://kss" }
```

`type`: `bedtime`, `deadline`, `kss_prompt`, `sleep_confirm`, `motivation`, `sync_conflict`.

**R5 `GET /quotes/random?context=deadline`** — `context`: `general | deadline | sleep | progress`

```json
{ "text": "...", "author": null, "source": "gemini", "context": "deadline" }
```

`source` is `"gemini"` or `"fallback"`.

### Home

**O1 `GET /home`** — one call for the Home screen (R60):

```json
{
  "date": "2026-10-22",
  "now": { "time": "...", "asleep": false, "process_s": 0.47, "process_c": 0.99,
           "kss_pred": 4.65, "kss_lo": 3.15, "kss_hi": 6.15, "alertness_score": 54 },
  "next_peak_window": { "start": "...", "end": "...", "mean_kss_pred": 3.65, "alertness_score": 67 },
  "tonight": { "...": "ProjectedSleep" },
  "today_events": [ { "...": "Event object (max 10)" } ],
  "upcoming_todos": [ { "...": "Todo object (max 3, nearest deadline)" } ],
  "sleep_debt_7d_minutes": 310,
  "last_night": { "...": "Sleep log object or null" },
  "needs_sleep_confirmation": true,
  "kss_checkin_due": false,
  "model": { "...": "ModelSummary" }
}
```

### System

**X1 `GET /health`** (Public) → `200 { "status": "ok", "db": "ok", "redis": "ok", "version": "1.0.0" }`, or `503` with the same shape when a dependency is down.

## 5. Changes since draft 1

Flutter code does not call any of these yet, but please re-check DTOs written from draft 1.

| Area | Change | Breaking? |
|---|---|---|
| **Draft 2.1** chronotype | `chronotype` enum `morning/intermediate/evening` → `lion/bear/wolf` (cut-offs 04:00 / 06:00 on MSFsc); new `spectrum`, `sleep_concern` (dolphin flag) | **Yes** |
| **Draft 2.1** C1 | Request adds `regular_schedule`, `sleep_quality`, `school_onset_shift_minutes`, `mctq.alarm_on_free_days`; response adds `spectrum`, `sleep_concern`, `sleep_shortfall_hours`, `typical_week`; `natural_*` now `MSFsc ± SDweek/2`; `422 RMEQ_REQUIRED` | Additive |
| **Draft 2.1** H1/H2, H8 | Profile adds `spectrum`, `sleep_concern`, `regular_schedule`, `sleep_quality`; H8 `sleep_state` adds `typical`, warning `TYPICAL_WEEK` | Additive |
| **Draft 2.1** scope | H9, P1–P4, K1–K3, B1, B2 marked *(later)* / `x-phase: later` — after the course project | No |
| H8 `/biorhythm` | Raw model values (`process_c` −1…1, `alertness` may be < 0) instead of 0–1; new `upper_threshold`, `lower_threshold`, `kss_pred/lo/hi`, `alertness_score`, `asleep`, `sleep_state`; windows get `mean_kss_pred`, `alertness_score`; new `days`, `timezone`, `model`, `projected_sleep`, `warnings` | **Yes** |
| S1 scheduler | `options.break_minutes` → `min_break_minutes`; default `block_minutes` 50 → 90; block `alertness` → `predicted_kss` + `alertness_score`; new `index`, `kind`; response adds `expires_at`, `from`, `to`, `stats`, `model` | **Yes** |
| Health profile | New `chronotype_source`, `morning_prep_minutes`, `mctq`, `mctq_result`, `rmeq_score`, `rmeq_category`, `screen_tracking_enabled`, `updated_at` | Additive |
| Sleep log | New `source`, `confirmed`, `confidence`, `created_at`, `updated_at` | Additive |
| H7 sleep debt | New `average_sleep_minutes`, `social_jetlag_hours`, `current_process_s`; daily `has_data`, `mid_sleep`, `is_free_day`; `debt_minutes` may be negative | Additive |
| Event | New `kind`; `occurrence_start` always present (null if not an instance) | Additive |
| Todo | New `scheduled_minutes`, `completed_at`; D1 adds `due_after`, `sort`, repeatable `status` | Additive |
| User | New `onboarding_completed` | Additive |
| Voice | Draft adds `description`, `difficulty`; response adds `parser`; request adds `reference_time` | Additive |
| Calendar | G1 adds `google_email`; G2 result adds `pulled`, optional body; S2 result adds `sync` | Additive |
| Reminders | New `kss_prompt_*`, `sleep_confirm_enabled`; quote adds `context` | Additive |
| New endpoints | C1, H9, P1–P4, K1–K3, B1, B2, G6–G8, O1 | New |
