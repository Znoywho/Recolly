# Recolly API (FastAPI)

Implements `docs/openapi.yaml` under `/api/v1`. Swagger UI: `http://localhost:8765/docs`.

## Run

```bash
cd server
python -m venv venv && source venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env   # fill in JWT_SECRET, Google OAuth client, TOKEN_ENCRYPTION_KEY
uvicorn app.main:app --reload --port 8765
```

Tables are created on startup (`Base.metadata.create_all`) until Alembic is set up, so a new
column on an existing table needs the table to be recreated.

## Tests

API tests need an **empty** PostgreSQL database (it is wiped on every run), e.g. a second
database in the docker compose container:

```bash
TEST_DATABASE_URL=postgresql+psycopg2://postgres:<password>@localhost:5433/recolly_test pytest
```

Without `TEST_DATABASE_URL` only the sleep-model unit tests run. Google is replaced by
`tests/fake_google.py`, so no network or OAuth client is needed.

## Not implemented yet

- OCR (T1, T2) and voice (V1): waiting for the Vintern / PhoWhisper / Gemini providers.
- Operations marked `x-phase: later` in the contract (screen events, KSS check-ins, Bayes).
- Sending FCM push notifications: R3/R4 only store device tokens.
