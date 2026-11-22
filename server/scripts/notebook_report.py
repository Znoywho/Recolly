"""Turn the notebook result files (notebooks/outputs/*.jsonl) into one HTML page for testing and demos.

    python scripts/notebook_report.py            # writes notebooks/report.html
    xdg-open notebooks/report.html
"""

import html
import json
import sys
from pathlib import Path
from statistics import mean

NOTEBOOKS_DIR = Path(__file__).resolve().parent.parent / "notebooks"

PAGE_STYLE = """
body { background: #fff7d6; font-family: system-ui, sans-serif; margin: 0; padding: 16px; color: #000; }
h1 { font-size: 2rem; font-weight: 900; margin: 0 0 16px; }
section { background: #fff; border: 3px solid #000; box-shadow: 4px 4px 0 #000; margin-bottom: 24px; padding: 16px; }
h2 { margin: 0 0 8px; }
.stats span { display: inline-block; background: #7df9c1; border: 2px solid #000; padding: 2px 8px;
              margin: 0 8px 8px 0; font-weight: 700; }
input { border: 2px solid #000; padding: 6px; width: 100%; max-width: 400px; margin-bottom: 8px; font: inherit; }
.table-wrap { max-height: 480px; overflow: auto; border: 2px solid #000; }
table { border-collapse: collapse; width: 100%; font-size: 0.85rem; }
th { position: sticky; top: 0; background: #ffd23f; }
th, td { border: 1px solid #000; padding: 4px 6px; text-align: left; vertical-align: top; }
"""

# Hide rows of one table that do not contain the search text.
FILTER_SCRIPT = """
document.querySelectorAll("input[data-table]").forEach(box => box.addEventListener("input", () => {
  const needle = box.value.toLowerCase();
  document.querySelectorAll("#" + box.dataset.table + " tbody tr").forEach(row => {
    row.hidden = !row.textContent.toLowerCase().includes(needle);
  });
}));
"""


def read_jsonl(path: Path) -> list[dict]:
    """Every non-empty line of a JSON Lines file, parsed."""
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def cell_text(value) -> str:
    """Show nested values (e.g. a parsed todo draft) as compact JSON, everything else as text."""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return "" if value is None else str(value)


def summarize_rows(rows: list[dict]) -> list[str]:
    """Badges for one file: row count, models used, mean processing time, error count."""
    stats = [f"{len(rows)} rows"]
    models = sorted({str(r.get("asr_model") or r.get("llm_model") or r.get("model")) for r in rows} - {"None"})
    if models:
        stats.append("model: " + ", ".join(models))
    times = [r["processing_seconds"] for r in rows if isinstance(r.get("processing_seconds"), (int, float))]
    if times:
        stats.append(f"mean {mean(times):.2f}s / row")
    if any("error" in r for r in rows):
        stats.append(f"{sum(1 for r in rows if r.get('error'))} errors")
    return stats


def render_section(table_id: str, title: str, rows: list[dict]) -> str:
    """One file as a card: stats badges, a search box and a scrollable table."""
    columns = list(dict.fromkeys(key for row in rows for key in row))  # union of keys, first-seen order
    head = "".join(f"<th>{html.escape(c)}</th>" for c in columns)
    body = "".join(
        "<tr>" + "".join(f"<td>{html.escape(cell_text(row.get(c)))}</td>" for c in columns) + "</tr>"
        for row in rows)
    badges = "".join(f"<span>{html.escape(s)}</span>" for s in summarize_rows(rows))
    return (f'<section><h2>{html.escape(title)}</h2><div class="stats">{badges}</div>'
            f'<input placeholder="Search…" data-table="{table_id}">'
            f'<div class="table-wrap"><table id="{table_id}"><thead><tr>{head}</tr></thead>'
            f"<tbody>{body}</tbody></table></div></section>")


def build_report(outputs_dir: Path) -> str:
    """The whole HTML page, one section per .jsonl file in outputs_dir."""
    files = sorted(outputs_dir.glob("*.jsonl"))
    sections = "".join(render_section(f"t{i}", f.name, read_jsonl(f)) for i, f in enumerate(files))
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>Notebook Results</title><style>{PAGE_STYLE}</style></head>"
            f"<body><h1>Recolly notebook results</h1>{sections or '<p>No .jsonl files found.</p>'}"
            f"<script>{FILTER_SCRIPT}</script></body></html>")


if __name__ == "__main__":
    output_path = Path(sys.argv[1]) if len(sys.argv) > 1 else NOTEBOOKS_DIR / "report.html"
    output_path.write_text(build_report(NOTEBOOKS_DIR / "outputs"), encoding="utf-8")
    print(f"Wrote {output_path}")
