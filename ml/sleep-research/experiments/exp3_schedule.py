"""Thí nghiệm 3: cùng thời khóa biểu, "giờ vàng" để học có khác nhau theo chronotype không?

Hai sinh viên ảo giống hệt nhau, chỉ khác chronotype (sơn ca vs cú đêm).
Quy trình y như trong app Recolly:
    màn hình -> HMM suy ra giấc ngủ -> Bayes học tham số cá nhân (14 ngày KSS)
    -> dự báo KSS cho một ngày -> chọn 3 khối học 90 phút tỉnh táo nhất
Recolly dùng OR-Tools CP-SAT. Ở đây dùng thuật toán tham lam cho dễ hiểu;
đầu vào (đường cong tỉnh táo) giống nhau, chỉ khác bộ giải.

Chạy: .venv/bin/python -m experiments.exp3_schedule
"""

import numpy as np

from experiments.common import AQUA, BLUE, INK2, ORANGE, SLEEP_FILL, hour_ticks, plt, save
from models.bayes_individual import BayesIndividual, fixed_param_kss
from models.chronotype import score_mctq
from models.screen_sleep import hmm_sleep
from models.synthetic import DEFAULT_TIMETABLE, in_class, make_student
from models.two_process import DT, phi_from_mid_sleep

TARGET_DAY = 17          # thứ Năm (17 % 7 = 3): chỉ có tiết chiều 13h-17h
BLOCK_H, N_BLOCKS = 1.5, 3
MEALS = [(11.5, 13.0), (18.0, 19.0)]
WAKE_BUFFER_H = 0.5      # bỏ 30 phút đầu sau khi dậy (quán tính giấc ngủ, mô hình chưa có)
BED_BUFFER_H = 1.0       # không học trong 1 giờ trước giờ ngủ


def plan_study_blocks(tod, kss, free):
    """Tham lam: lần lượt chọn khối 90 phút có KSS trung bình thấp nhất, không chồng lấn."""
    n = int(round(BLOCK_H / DT))
    free = free.copy()
    blocks = []
    for _ in range(N_BLOCKS):
        best, best_score = None, np.inf
        for i in range(0, tod.size - n):
            if free[i:i + n].all() and kss[i:i + n].mean() < best_score:
                best, best_score = i, kss[i:i + n].mean()
        if best is None:
            break
        blocks.append((tod[best], tod[best] + BLOCK_H, best_score))
        free[max(0, best - 6):best + n + 6] = False  # nghỉ ít nhất 30 phút giữa hai khối
    return sorted(blocks)


def main():
    rng = np.random.default_rng(7)
    people = [("Sơn ca", 15.5, BLUE), ("Cú đêm", 19.5, ORANGE)]
    fig, axes = plt.subplots(2, 1, figsize=(9, 6), sharex=True)
    for ax, (name, phi_true, color) in zip(axes, people):
        st = make_student(rng, days=21, phi=phi_true, chi_w=18.2,
                          procrastination_mean=20, phone_rate=0.3)
        phi_mctq = phi_from_mid_sleep(score_mctq(st.mctq).MSFsc)
        mask = hmm_sleep(st.t, st.screen, phi_mctq)
        b = BayesIndividual(st.t, mask, phi_mctq, 1.0)
        train = (st.t[st.kss_idx] >= 48) & (st.t[st.kss_idx] < TARGET_DAY * 24)
        b.update(st.kss_idx[train], st.kss[train])
        s = b.summary()

        day = (st.t >= TARGET_DAY * 24 + 6) & (st.t < TARGET_DAY * 24 + 26)
        idx = np.flatnonzero(day)
        tod = st.t[idx] - TARGET_DAY * 24
        kss = fixed_param_kss(st.t, mask, idx, s["phi"], s["chi_w"])
        awake = ~mask[idx]
        wake_t = tod[np.argmax(awake)]
        evening_sleep = np.flatnonzero(~awake & (tod > 15))
        bed_t = tod[evening_sleep[0]] if evening_sleep.size else tod[-1]
        free = awake & (tod >= wake_t + WAKE_BUFFER_H) & (tod <= bed_t - BED_BUFFER_H)
        free &= ~np.array([in_class(h % 24, TARGET_DAY % 7, DEFAULT_TIMETABLE) for h in tod])
        free &= ~np.array([any(a <= h < e for a, e in MEALS) for h in tod])
        blocks = plan_study_blocks(tod, kss, free)

        print(f"{name}: phi thật {phi_true:.1f}h, MCTQ -> {phi_mctq:.1f}h, Bayes -> {s['phi']:.1f}h "
              f"(±{s['phi_sd'] * 60:.0f}'), chi_w {s['chi_w']:.1f}h")
        print(f"   dậy {wake_t:.2f}h, ngủ dự kiến {bed_t % 24:.2f}h; khối học được chọn: "
              + ", ".join(f"{a:05.2f}-{e:05.2f}h (KSS {k:.1f})" for a, e, k in blocks))

        kss_plot = np.where(awake, np.clip(kss, 1, 9), np.nan)
        ax.fill_between(tod, 0, 1, where=~awake, color=SLEEP_FILL, alpha=0.6, lw=0,
                        transform=ax.get_xaxis_transform(), label="ngủ (suy ra)")
        for k, (a, e) in enumerate(DEFAULT_TIMETABLE[TARGET_DAY % 7]):
            ax.axvspan(a, e, color=INK2, alpha=0.12, lw=0, label="tiết học" if k == 0 else None)
        for k, (a, e, _) in enumerate(blocks):
            ax.axvspan(a, e, color=AQUA, alpha=0.35, lw=0, label="khối học được xếp" if k == 0 else None)
        ax.plot(tod, kss_plot, color=color, label="KSS dự báo")
        ax.set_ylim(9.2, 0.8)  # đảo trục: càng lên cao càng tỉnh táo
        ax.set_ylabel("KSS (thấp = tỉnh táo)")
        ax.set_title(f"{name}: chronotype học được ≈ {s['phi']:.1f}h")
        ax.legend(loc="lower right", ncol=4, fontsize=8)
    axes[-1].set_xlim(6, 26)
    hour_ticks(axes[-1], 6, 26, 2)
    fig.suptitle("Cùng thời khóa biểu thứ Năm, giờ vàng để học khác nhau theo chronotype",
                 fontweight="bold")
    save(fig, "fig3_study_blocks.png")


if __name__ == "__main__":
    main()
