"""Try the Ollama client from the terminal.

Usage:
    python scripts/ollama_demo.py                 # one quote per persona + todo extraction
    python scripts/ollama_demo.py "Mai thi Toán"  # extract a todo from your own sentence
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.service.llm.ollama_client import OllamaClient  # noqa: E402
from app.service.quotes import PERSONAS, build_quote_prompt  # noqa: E402

TODO_PROMPT = "Trích xuất một việc cần làm từ câu nói tiếng Việt của sinh viên."
TODO_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "deadline_text": {"type": "string"},
    },
    "required": ["title", "deadline_text"],
}


def print_quote_for_each_persona(client: OllamaClient, sleep_debt_hours: float, next_deadline: str) -> None:
    """Ask the model for one quote per persona so the voices can be compared."""
    for persona in PERSONAS:
        system_prompt = build_quote_prompt(persona, sleep_debt_hours, next_deadline)
        quote = client.generate_text(system_prompt, "Cho tui một câu đi.", temperature=0.9)
        print(f"[{persona}] {quote}")


def run_demo(user_message: str) -> None:
    """Print the available models, the persona quotes and one JSON extraction."""
    client = OllamaClient()
    print("Models on server:", client.list_model_names())
    print_quote_for_each_persona(client, sleep_debt_hours=3.5, next_deadline="Báo cáo AI, 9 giờ sáng mai")
    print("Todo:", client.generate_json(TODO_PROMPT, user_message, TODO_SCHEMA))


if __name__ == "__main__":
    run_demo(sys.argv[1] if len(sys.argv) > 1 else "Mai tui phải nộp báo cáo AI lúc 9 giờ sáng")
