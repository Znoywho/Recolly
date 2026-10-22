"""Phần dùng chung cho các thí nghiệm: style biểu đồ, thư mục kết quả, nhóm sinh viên ảo."""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

from models.synthetic import make_student  # noqa: E402

RESULTS = Path(__file__).resolve().parent.parent / "results"
RESULTS.mkdir(exist_ok=True)

# Bảng màu phân loại đã kiểm định (skill dataviz), dùng theo đúng thứ tự
BLUE, ORANGE, AQUA, YELLOW = "#2a78d6", "#eb6834", "#1baf7a", "#eda100"
INK, INK2, MUTED, GRID, SURFACE = "#0b0b0b", "#52514e", "#8a8984", "#e6e5e0", "#fcfcfb"
SLEEP_FILL = "#c9c8c1"

N_STUDENTS = 40
DAYS = 28
SEED = 2026

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": MUTED, "axes.labelcolor": INK2, "text.color": INK,
    "xtick.color": INK2, "ytick.color": INK2, "axes.grid": True, "grid.color": GRID,
    "grid.linewidth": 0.8, "axes.spines.top": False, "axes.spines.right": False,
    "lines.linewidth": 2, "font.size": 10, "axes.titlesize": 11, "axes.titleweight": "bold",
    "legend.frameon": False, "figure.dpi": 110,
})


def cohort(n=N_STUDENTS, days=DAYS, seed=SEED):
    rng = np.random.default_rng(seed)
    return [make_student(rng, days=days) for _ in range(n)], rng


def save(fig, name):
    path = RESULTS / name
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    print(f"  -> đã lưu {path.relative_to(RESULTS.parent)}")


def hour_ticks(ax, start=0, end=24, step=3):
    ticks = np.arange(start, end + 0.1, step)
    ax.set_xticks(ticks)
    ax.set_xticklabels([f"{int(h % 24):02d}h" for h in ticks])
