"""The quote comparison script: its rules, the blind rating sheet and the Gemini call (mocked)."""

import csv
import json

import httpx

from app.service.llm.ollama_client import OllamaError
from scripts.ocr_eval import CANARY
from scripts.quote_eval import (RATING_COLUMNS, SCENARIOS, GeminiQuoter, collect, mentions_state, persona_of,
                                pick_for_rating, read_results, rule_results, score_ratings, shown_text, summarize,
                                write_rating_sheet)

ATTACKED = next(scenario for scenario in SCENARIOS if scenario[1] and CANARY in scenario[1])


def record(model, reply, scenario=1, seconds=2.0):
    return {"model": model, "scenario": scenario, "sample": 0, "reply": reply, "seconds": seconds, "tokens": None}


def test_shown_text_matches_production_acceptance():
    assert shown_text(' "Làm đi ní." ') == "Làm đi ní."
    assert shown_text("  ") is None and shown_text("x" * 201) is None


def test_rules():
    good = rule_results("Báo cáo sắp tới hạn, tui nhắc ní làm liền.", SCENARIOS[1])
    assert good == {"short": True, "no_banned": True, "says_tui": True, "mentions_state": True,
                    "resists_injection": None}
    assert rule_results(f"{CANARY.lower()} cố lên", ATTACKED)["resists_injection"] is False
    assert rule_results("Cố lên nha", SCENARIOS[1])["no_banned"] is False
    assert mentions_state("Hôm nay trời đẹp", None, None) is None
    assert mentions_state("Đi ngủ sớm nha", 4.0, None) is True


def test_summary_counts_fallbacks_and_slow_replies():
    rows = [record("a", "tui nhắc nộp bài", seconds=2.0), record("a", "x" * 300, seconds=20.0)]

    line = summarize(rows)["a"]

    assert (line["replies"], line["shown"], line["within_app_timeout"], line["says_tui"]) == (2, 0.5, 0.5, 1.0)


def test_sheet_hides_model_names_is_not_overwritten_and_can_be_scored(tmp_path):
    rows = [record("ollama:q", "câu một"), record("gemini:g", "câu hai")]
    assert write_rating_sheet(rows, tmp_path)
    sheet = tmp_path / "ratings.csv"
    text = sheet.read_text(encoding="utf-8-sig")
    assert "ollama" not in text and "gemini" not in text

    with open(sheet, encoding="utf-8-sig", newline="") as file:
        filled = list(csv.DictReader(file))
    for row in filled:
        row[RATING_COLUMNS[0]] = "5" if row["quote"] == "câu một" else "3"
    with open(sheet, "w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=filled[0].keys())
        writer.writeheader()
        writer.writerows(filled)

    assert not write_rating_sheet(rows, tmp_path)
    scores = score_ratings(tmp_path)
    assert scores["ollama:q"][RATING_COLUMNS[0]] == (5.0, 1) and scores["gemini:g"][RATING_COLUMNS[0]] == (3.0, 1)


def test_every_persona_is_asked_with_its_own_prompt_and_old_records_count_as_genz(tmp_path):
    prompts = []

    class Echo:
        name = "echo"

        def generate(self, prompt):
            prompts.append(prompt)
            return "ok", 1.0, None

    results = tmp_path / "results.jsonl"
    results.write_text(json.dumps(record("echo", "cũ", scenario=0)) + "\n", encoding="utf-8")  # no persona field

    collect(Echo(), results, 1, ("genz", "coach"))

    saved = read_results(results)
    assert sorted(persona_of(row) for row in saved) == ["coach"] * 12 + ["genz"] * 12
    assert len(prompts) == 23 + 1 and any("Huấn luyện viên" in prompt for prompt in prompts)


def test_rating_pick_uses_the_same_questions_for_both_models():
    rows = [{**record(model, "tui", scenario=scenario), "persona": persona}
            for model in ("a", "b") for persona in ("genz", "coach") for scenario in range(12)]

    picked = pick_for_rating(rows, 3)

    def questions(model):
        return {(row["persona"], row["scenario"]) for row in picked if row["model"] == model}

    assert len(picked) == 2 * 2 * 3 and questions("a") == questions("b")
    assert pick_for_rating(rows, None) == rows


def test_gemini_call_sends_the_prompt_and_excludes_rate_limit_waits():
    requests = []
    replies = [httpx.Response(429), httpx.Response(200, json={
        "status": "completed", "usage": {"total_tokens": 50},
        "steps": [{"type": "model_output", "content": [{"type": "text", "text": "Làm đi."}]}]})]

    def handle(request):
        requests.append(json.loads(request.content))
        return replies.pop(0)

    quoter = GeminiQuoter("m", "key", transport=httpx.MockTransport(handle), sleep=lambda _: None)

    text, seconds, tokens = quoter.generate("system rules")

    assert (text, tokens) == ("Làm đi.", 50) and 0 <= seconds < 5
    assert requests[-1]["system_instruction"] == "system rules" and requests[-1]["store"] is False


def test_collect_skips_a_dead_model_and_resumes(tmp_path):
    class Dead:
        name = "dead"

        def generate(self, prompt):
            raise OllamaError("down")

    class Alive:
        name, calls = "alive", 0

        def generate(self, prompt):
            Alive.calls += 1
            return "ok", 1.0, None

    results = tmp_path / "results.jsonl"
    collect(Dead(), results, 1)
    collect(Alive(), results, 1)
    collect(Alive(), results, 1)

    assert len(read_results(results)) == len(SCENARIOS) and Alive.calls == len(SCENARIOS) + 1  # + one warm-up
