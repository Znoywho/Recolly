# Recolly

## Project goals
- Android app that helps university students build schedules quickly via voice input and photos (e.g. a photo of their class timetable).
- Schedule study sessions and to-dos according to the user's circadian rhythm, using Borbély's Two-Process Model of Sleep Regulation (Process S – sleep pressure, Process C – circadian rhythm).
- Sync schedules with Google Calendar.
- UI style: Gen Z Neo-brutalism.

## Tech stack
- Backend: Python, FastAPI + SQLAlchemy — `server/app/`
- Database: PostgreSQL
- Frontend: Flutter (target: Android) — `client/lib/` (`core/` shared code, `features/<feature>/` per feature)
- Scheduling/optimization: OR-Tools CP-SAT
- AI: Vintern-1B-v3_5 (Vietnamese OCR), PhoWhisper (Vietnamese ASR), Google Gemini (LLM)
- Calendar: Google Calendar API (OAuth 2.0)
- Deployment: Docker, Kubernetes, Redis

## Common commands
- Run everything: `docker compose up --build`
- Backend dev: `cd server && uvicorn app.main:app --reload`
- Flutter: `cd client && flutter pub get && flutter run`
- Tests: `pytest` (server), `flutter test` (client)

## Team ownership
Task IDs (Rxx) refer to the team task board.

### Member 1 — Lê Thiên Hạo: Backend (all of `server/`)
- Server setup, PostgreSQL schema, Google OAuth on backend (R03, R04, R08)
- OCR: upload endpoint, Vintern integration, normalize OCR output to timetable, OCR testing (R09–R12)
- CRUD APIs: timetable, sleep log, todo/deadline (R15, R17, R21)
- Process S/C model: spec, implementation, API + tests (R18–R20)
- CP-SAT scheduler: constraint spec, base solver, class/deadline constraints, generate & save schedule API (R24–R27)
- Google Calendar: one-way sync, sync testing, two-way sync + conflict handling (R30, R31, R45)
- Sleep/deadline reminder rules on server (R39)
- PhoWhisper speech-to-text API, transcript → todo (R42, R43)
- Gemini integration + fallback quotes (R49)

### Member 2 — Cao Lê Huy Hoàng: Flutter data & feature screens
- Flutter API client + DTOs (R06), Google sign-in (R07) — `features/auth/`
- Timetable import screen, scan result & edit subject screen, connect OCR → save timetable (R13, R14, R16)
- Todo list UI + connect to API (R22, R23)
- Weekly calendar screen, show suggested schedule, event detail screen (R28, R29, R58) — `features/caldendar/`
- Google Calendar connect UI, push-schedule flow, two-way sync status (R32, R33, R46) — `features/sync/`
- Voice input screen, recording → transcript → todo (R41, R44)
- Profile screen (R61)

### Member 3 — Nguyễn Vũ Hoàng: Flutter foundation, design & wellbeing screens
- Flutter app skeleton (R05) — `main.dart`, `app.dart`, `core/`
- Figma design for 17 screens (R53), design system & Flutter theme (R54)
- Splash, onboarding, sleep profile (R55); main navigation & Home screen + real data (R56, R60)
- Sleep screen: sleep/wake input, sleep debt chart (R34, R35); Biorhythm screen (R59)
- Reminder settings, Flutter notifications, motivation popup (R38, R40, R50)
- Todo/deadline create & edit form (R57); Scanning & scan-failed screens (R62)

### Shared
- Members 2 + 3: Phase 1 UI/UX review (R63)
- Whole team: OpenAPI contract (R01), timetable photo dataset (R02), integration tests, demos, regression & final acceptance (R36, R37, R47, R48, R51, R52)

## Rules
- Only modify code within the area the current user owns (see `CLAUDE.local.md` for who the current user is). Do NOT edit other members' areas.
- If you find a bug in someone else's area, do not fix it. Report it instead: file, line, how to reproduce, suggested fix, and which member owns it.
- Foundation files — warn clearly and ask before changing: `server/app/config.py`, DB models/migrations, `docker-compose.yml`, `Dockerfile`s, `.gitignore`, the OpenAPI contract / request-response schemas, `client/lib/main.dart`, `client/lib/app.dart`, `client/lib/core/`, `pubspec.yaml`, `requirements.txt` / `pyproject.toml`.
- API contract changes affect both backend and Flutter: never change an endpoint's shape without flagging it for the whole team.
- Never hardcode secrets (passwords, API keys, OAuth credentials); use environment variables / `.env`.
- Never commit directly to `main`; use feature branches.

## UI: Neo-brutalism
- Thick black borders (2–3px), hard shadows with no blur (offset ~4px 4px).
- Bright, high-contrast background colors; bold typography.

## Language
- Always respond to the user in Vietnamese.
- Code, comments, and commit messages: English.
