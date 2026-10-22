"""Thí nghiệm 1: suy ra giấc ngủ và chronotype từ dữ liệu màn hình.

Câu hỏi:
  1. Đoán giờ ngủ/thức từ màn hình sai bao nhiêu phút?
     So sánh: luật "khoảng tắt dài nhất" vs HMM (prior quần thể) vs HMM (prior MCTQ).
  2. Đoán chronotype (pha phi) chính xác tới đâu?
     So sánh: MCTQ tự khai vs MCTQ tính từ giấc ngủ suy ra bằng màn hình.

Chạy: .venv/bin/python -m experiments.exp1_screen_sleep
"""

import numpy as np

from experiments.common import (AQUA, BLUE, INK2, ORANGE, SLEEP_FILL, cohort, hour_ticks, plt, save)
from models.chronotype import score_mctq
from models.screen_sleep import episode_errors, heuristic_sleep, hmm_sleep
from models.synthetic import mctq_from_sleep
from models.two_process import circular_diff_hours, phi_from_mid_sleep

POP_PHI = 17.4  # pha trung bình của quần thể (prior khi chưa biết gì về người dùng)


def main():
    students, _ = cohort()
    methods = {"Khoảng tắt dài nhất": [], "HMM, prior quần thể": [], "HMM, prior MCTQ": []}
    phi_err = {"MCTQ tự khai": [], "MCTQ từ màn hình": []}

    for st in students:
        phi_mctq = phi_from_mid_sleep(score_mctq(st.mctq).MSFsc)
        masks = {
            "Khoảng tắt dài nhất": heuristic_sleep(st.t, st.screen),
            "HMM, prior quần thể": hmm_sleep(st.t, st.screen, POP_PHI),
            "HMM, prior MCTQ": hmm_sleep(st.t, st.screen, phi_mctq),
        }
        for name, mask in masks.items():
            on, off, missed = episode_errors(st.t, st.asleep, mask)
            methods[name].append((np.abs(on).mean(), np.abs(off).mean(), missed,
                                  (mask == st.asleep).mean()))

        phi_screen = phi_from_mid_sleep(score_mctq(
            mctq_from_sleep(st.t, masks["HMM, prior quần thể"], st.timetable)).MSFsc)
        phi_err["MCTQ tự khai"].append(circular_diff_hours(phi_mctq, st.params.phi))
        phi_err["MCTQ từ màn hình"].append(circular_diff_hours(phi_screen, st.params.phi))

    print("1) Suy ra giấc ngủ chính mỗi đêm (trung bình trên", len(students), "sinh viên):")
    print(f"   {'phương pháp':<22}{'sai số giờ ngủ':>16}{'sai số giờ dậy':>16}{'đêm bị sót':>12}{'độ chính xác':>14}")
    summary = {}
    for name, rows in methods.items():
        r = np.array(rows)
        summary[name] = r
        print(f"   {name:<22}{r[:, 0].mean():>12.1f} phút{r[:, 1].mean():>12.1f} phút"
              f"{r[:, 2].mean():>12.2f}{r[:, 3].mean() * 100:>13.1f}%")

    print("2) Ước lượng chronotype (pha phi), sai số so với giá trị thật:")
    for name, e in phi_err.items():
        e = np.array(e)
        print(f"   {name:<20} sai số tuyệt đối TB {np.abs(e).mean() * 60:5.1f} phút, "
              f"lệch hệ thống {e.mean() * 60:+5.1f} phút")

    # Hình 1: 7 ngày của một sinh viên
    st = students[3]
    phi_mctq = phi_from_mid_sleep(score_mctq(st.mctq).MSFsc)
    rows = [("giấc ngủ thật", st.asleep, INK2),
            ("khoảng tắt dài nhất", heuristic_sleep(st.t, st.screen), ORANGE),
            ("HMM + MCTQ", hmm_sleep(st.t, st.screen, phi_mctq), BLUE)]
    days = range(14, 21)
    fig, axes = plt.subplots(len(days), 1, figsize=(9, 6.5), sharex=True)
    weekday = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
    for ax, d in zip(axes, days):
        win = (st.t >= d * 24 + 12) & (st.t < d * 24 + 36)
        tt = st.t[win] - d * 24
        for k, (_, mask, color) in enumerate(rows):
            m = mask[win]
            ax.fill_between(tt, 2 - k - 0.35, 2 - k + 0.35, where=m, color=color, lw=0, step="post")
        on_t = tt[st.screen[win]]
        ax.plot(on_t, np.full(on_t.size, 3), "|", color=AQUA, ms=7, mew=1.2)
        ax.set_ylim(-0.6, 3.6)
        ax.set_yticks([])
        ax.set_ylabel(f"{weekday[(d + 1) % 7]}", rotation=0, labelpad=12, va="center")
        ax.grid(axis="y", visible=False)
    axes[-1].set_xlim(12, 36)
    hour_ticks(axes[-1], 12, 36, 3)
    handles = [plt.Line2D([], [], color=AQUA, marker="|", ls="", ms=10, mew=1.5, label="bật màn hình")]
    handles += [plt.Rectangle((0, 0), 1, 1, color=c, label=n) for n, _, c in rows]
    fig.legend(handles=handles, loc="lower center", ncol=4, bbox_to_anchor=(0.5, -0.02))
    fig.suptitle("Một tuần của một sinh viên ảo: màn hình (trên) và ba cách xác định giấc ngủ\n"
                 "(mỗi hàng là một đêm, nhãn = thứ của buổi sáng thức dậy)", fontweight="bold")
    fig.subplots_adjust(hspace=0.15, bottom=0.1)
    save(fig, "fig1a_screen_raster.png")

    # Hình 2: sai số giờ ngủ / giờ dậy
    fig, ax = plt.subplots(figsize=(7.5, 3.4))
    names = list(summary)
    x = np.arange(len(names))
    w = 0.36
    on = [summary[n][:, 0].mean() for n in names]
    off = [summary[n][:, 1].mean() for n in names]
    b1 = ax.bar(x - w / 2 - 0.01, on, w, color=BLUE, label="giờ ngủ")
    b2 = ax.bar(x + w / 2 + 0.01, off, w, color=ORANGE, label="giờ dậy")
    ax.bar_label(b1, fmt="%.0f'", padding=2, color=INK2)
    ax.bar_label(b2, fmt="%.0f'", padding=2, color=INK2)
    ax.set_xticks(x)
    ax.set_xticklabels(names)
    ax.set_ylabel("sai số tuyệt đối TB (phút)")
    ax.set_title("Sai số suy ra giấc ngủ từ màn hình (thấp hơn là tốt hơn)")
    ax.legend()
    save(fig, "fig1b_sleep_error.png")


if __name__ == "__main__":
    main()
