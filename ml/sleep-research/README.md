# Sleep research code

Research code behind `docs/research/NGHIEN_CUU.md`: two-process model, MCTQ, screen-based HMM,
Bayesian personalisation, and four experiments on synthetic students. Comments and figure labels
are in Vietnamese because this is the original research workspace; production code lives in
`server/app/service/sleep/`.

```bash
cd ml/sleep-research
uv venv .venv && uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -m experiments.exp0_two_process
.venv/bin/python -m experiments.exp1_screen_sleep
.venv/bin/python -m experiments.exp2_personalization   # ~30 s
.venv/bin/python -m experiments.exp3_schedule
```

Figures are written to `results/`.
