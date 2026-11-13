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

Without `TEST_DATABASE_URL` only the unit tests run (sleep model, deadline rules, voice todo parser,
voice endpoint with faked models). Google is replaced by `tests/fake_google.py`, so no network or
OAuth client is needed.

## Not implemented yet

- OCR (T1, T2): waiting for the Vintern provider.
- Operations marked `x-phase: later` in the contract (screen events, KSS check-ins, Bayes).
- Sending FCM push notifications: R3/R4 only store device tokens.

## Voice → todo pipeline (V1)

```
 audio (.m4a)
   │
   ▼
 ┌─────────────────────────────┐
 │ 1. ASR  PhoWhisper          │  app/service/voice/transcriber.py
 │    audio → Vietnamese text  │  metric: WER, keyword recall
 └──────────────┬──────────────┘
                │ transcript  "tối thứ sáu này tám giờ ôn thi với bạn"
        ┌───────┴────────────────────────────────┐
        ▼                                        ▼
 ┌──────────────────────────┐          ┌──────────────────────────┐
 │ 2. LLM  qwen2.5 (Ollama) │          │ 3. Rules                 │
 │    JSON schema output    │          │    time_parser.py        │
 │    title, category,      │          │    deadline_at           │
 │    priority (+ repaired  │          │    (~30 µs, no ML)       │
 │    transcript)           │          │    metric:               │
 │    metric: category_acc, │          │    deadline_day_acc      │
 │    title token-F1        │          │                          │
 └──────────────┬───────────┘          └────────────┬─────────────┘
                │ {title: "Ôn thi với bạn",          │ 2026-11-13T20:00+07:00
                │  category: exam, priority: medium} │
                └──────────────────┬────────────────┘
                                   ▼
                     todo_draft  → user confirms in the app
                     end-to-end metric: Task Success Rate (TSR)
```

`app/service/voice/todo_parser.py` glues 2 + 3; `app/api/voice_api.py` serves `POST /voice/transcribe`
(rule-only fallback when Ollama is unreachable). The LLM's own `deadline_at` is discarded: small models are
good at language and bad at calendar arithmetic (measured: 49–84 % correct days vs 100 % for the rules on
clean transcripts).

### Decision (2026-11-13)

Two modes, switched by environment variables:

| mode | `VOICE_LLM_MODEL` | `VOICE_REPAIR_TRANSCRIPT` | TSR clean | TSR real audio (medium) | where Ollama runs |
|---|---|---|---|---|---|
| **demo** (default) | `qwen2.5:14b` | `1` (A2a: LLM repairs mishearings first) | 0.87 | **0.73** | Kaggle GPU via `notebooks/kaggle_ollama.ipynb` + tunnel (`OLLAMA_BASE_URL`) |
| light | `qwen2.5:7b` | `0` | 0.90 | 0.66 | a local Ollama |

n = 62 clips, CI ≈ ±0.11. Measured facts behind the choice:
- Transcript repair only works from 14b up: 7b makes transcripts *worse* (WER 0.166 → 0.197), 14b better (→ 0.135).
- qwen2.5:14b ≈ 7b on category/title with clean text (0.912 vs 0.897), so the extra cost buys only the repair step.
- Few-shot examples hurt every model (copied into titles). gemma3 4b/12b break on long prompts.
- A separate spelling-correction model (`bmd1905/vietnamese-correction-v2`) fixes typos, not mishearings: WER 0.166 → 0.165, and it deletes English words. Rejected.
- PhoWhisper on an 8-core CPU: small RTF 2.7, medium RTF 10.4 → ASR also needs the GPU for anything but small.

The remaining end-to-end losses are ASR errors on English terms (`GitHub`, `Flutter`) that corrupt the title.

### Layer 3: rule-based deadline parser (`app/service/voice/time_parser.py`)

Closed vocabulary of ~40 Vietnamese time words, no model. Steps:

1. **Normalize**: NFC, lowercase, strip punctuation, `19h30` / `8:30` → `19 giờ 30`.
2. **Clock**: `<number> giờ [rưỡi | <number> (phút) | kém <number>]`, then the nearest part of day
   (`sáng/trưa/chiều/tối/đêm`) converts to 24 h: `bảy giờ tối` → 19:00, `tám giờ kém mười lăm` → 07:45.
   Spoken numbers are parsed (`mười lăm` = 15, `hai mươi mốt` = 21).
3. **Date**, first rule that matches wins:
   1. explicit `ngày/mùng N [tháng M]`
   2. relative: `hôm nay/tối nay` = +0, `mai` = +1, `mốt/ngày kia` = +2, `N ngày nữa`, `N tuần nữa`
   3. weekday: `thứ hai…bảy`, `thứ 2…7`, `chủ nhật`, `cuối tuần` (= Sunday); `tuần sau/tới` = +1 week,
      `tuần sau nữa` = +2; a weekday already past this week rolls to next week
   4. clock only: today if that time is still ahead, otherwise tomorrow
   5. nothing found: `deadline_at = null` (never guessed)
4. Day without clock → 23:59.

Deliberately **not** done here: repairing ASR mishearings (`hứa sáo` for `thứ sáu`, handled by the LLM in demo
mode), falling back to the LLM deadline when nothing is found (measured: worse, the LLM invents deadlines),
recurring events (`mỗi thứ hai`, planned).

### Layer 2: category rules

`notebooks/data/category_guide.md` is the single source of truth for `category`, used both to label the eval
set and inside the LLM prompt: `exam` (a named test) → `assignment` (produce and submit something) → `study` →
`personal` → `other` (school admin and the rest), first match wins.

### Evaluation

`notebooks/voice_eval.ipynb` (local, CPU) and `notebooks/kaggle_voice_eval.ipynb` (GPU sweep: 3 PhoWhisper sizes
× 6 Ollama LLMs × prompt variants, noise robustness, A2a repair, paired McNemar tests). Eval set:
`notebooks/data/voice_eval.jsonl`, 68 sentences (62 with audio, 3 speakers, recording script in
`notebooks/data/recording_script.md`). Results are cached in `notebooks/outputs/*.jsonl`.
