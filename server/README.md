# Recolly backend

FastAPI + SQLAlchemy service for the Recolly app. See the repo root `.claude/CLAUDE.md` for the full project
description; this file documents the parts that live under `server/`.

## Voice → todo pipeline

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
 │ 2. LLM  qwen2.5:7b       │          │ 3. Rules                 │
 │    via Ollama, JSON      │          │    time_parser.py        │
 │    title, category,      │          │    deadline_at           │
 │    priority              │          │    (~30 µs, no ML)       │
 │    metric: category_acc, │          │    metric:               │
 │    title token-F1        │          │    deadline_day_acc      │
 └──────────────┬───────────┘          └────────────┬─────────────┘
                │ {title: "Ôn thi với bạn",          │ 2026-11-13T20:00+07:00
                │  category: exam, priority: medium} │
                └──────────────────┬────────────────┘
                                   ▼
                     todo_draft  → user confirms in the app
                     end-to-end metric: Task Success Rate (TSR)
```

The LLM's own `deadline_at` is discarded: small models are good at language and bad at calendar arithmetic
(measured: 49 % correct days vs 100 % for the rules on clean transcripts).

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

Deliberately **not** done here: repairing ASR mishearings (`hứa sáo` for `thứ sáu`, a layer-1 problem),
falling back to the LLM deadline when nothing is found (measured: worse, the LLM invents deadlines), recurring
events (`mỗi thứ hai`, planned).

### Layer 2: category rules

`notebooks/data/category_guide.md` is the single source of truth for `category`, used both to label the eval
set and inside the LLM prompt: `exam` (a named test) → `assignment` (produce and submit something) → `study` →
`personal` → `other` (school admin and the rest), first match wins.

## Evaluation

`notebooks/voice_eval.ipynb` (local, CPU) and `notebooks/kaggle_voice_eval.ipynb` (GPU sweep: 3 PhoWhisper sizes
× 4 Ollama LLMs × prompt variants, noise robustness, paired McNemar tests). Eval set:
`notebooks/data/voice_eval.jsonl`, 68 sentences (62 with audio, 3 speakers, recording script in
`notebooks/data/recording_script.md`). Results are cached in `notebooks/outputs/*.jsonl`.

Best configuration so far (2026-11-13): PhoWhisper-medium → qwen2.5:7b with the `cal21_cat2` prompt → rule
deadline. TSR 0.90 on clean transcripts, 0.66 end-to-end on real audio (n = 62, CI ≈ ±0.11); the remaining
end-to-end losses are ASR errors on English terms that corrupt the title.

## Common commands

```bash
uvicorn app.main:app --reload     # dev server
pytest                            # tests (tests/test_time_parser.py covers the deadline rules)
```
