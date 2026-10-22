"""Thí nghiệm 0: kiểm tra mô hình hai quá trình có đúng như bài báo không.

  (a) Khi a = 0, thời lượng ngủ/thức phải khớp Skeldon & Dijk: 5.8h / 16.8h / 22.6h.
  (b) Khi có nhịp ngày đêm (a = 0.12), chu kỳ ngủ-thức bị kéo về đúng 24h.
  (c) Dịch pha phi (chronotype) -> giấc ngủ dịch đúng bấy nhiêu giờ.

Chạy: .venv/bin/python -m experiments.exp0_two_process
"""

import numpy as np

from experiments.common import BLUE, INK2, MUTED, ORANGE, SLEEP_FILL, hour_ticks, plt, save
from models.two_process import (Params, alertness, lower_threshold, mean_mid_sleep, natural_period,
                                simulate_free, sleep_episodes, upper_threshold)


def main():
    p = Params()

    print("(a) Không có nhịp ngày đêm (a = 0):")
    t_sleep, t_wake, t_nat = natural_period(p)
    print(f"    ngủ {t_sleep:.2f}h, thức {t_wake:.2f}h, chu kỳ {t_nat:.2f}h  (bài báo: 5.8 / 16.8 / 22.6)")
    t, _, s = simulate_free(p.with_(a=0), days=10)
    eps = [(on, off) for on, off in sleep_episodes(t, s) if off < t[-1]]
    onsets = np.array([on for on, _ in eps])
    print(f"    mô phỏng số: chu kỳ = {np.diff(onsets)[2:].mean():.2f}h")

    print("(b) Có nhịp ngày đêm (a = 0.12):")
    t, H, s = simulate_free(p, days=12)
    eps = [(on, off) for on, off in sleep_episodes(t, s) if on > 5 * 24 and off < t[-1]]
    onsets = np.array([on for on, _ in eps])
    print(f"    chu kỳ = {np.diff(onsets).mean():.2f}h, ngủ lúc {onsets[-1] % 24:.2f}h, "
          f"thời lượng {np.mean([off - on for on, off in eps]):.2f}h")

    print("(c) Dịch pha chronotype:")
    for phi in [14.0, 16.0, 18.0, 20.0]:
        print(f"    phi = {phi:4.1f}h -> giữa giấc ngủ {mean_mid_sleep(p.with_(phi=phi)):.2f}h")

    # Hình 1: tái tạo hình 1b của Skeldon & Dijk
    show = (t >= 8 * 24) & (t < 11 * 24)
    tt = t[show] - 8 * 24
    fig, ax = plt.subplots(figsize=(9, 3.6))
    ax.fill_between(tt, 0, 1, where=s[show], color=SLEEP_FILL, alpha=0.6, lw=0, label="đang ngủ",
                    transform=ax.get_xaxis_transform())
    ax.plot(tt, upper_threshold(t[show], p), color=MUTED, lw=1.5, ls="--", label="ngưỡng trên H⁺(t)")
    ax.plot(tt, lower_threshold(t[show], p), color=MUTED, lw=1.5, ls=":", label="ngưỡng dưới H⁻(t)")
    ax.plot(tt, H[show], color=BLUE, label="áp lực ngủ H(t) (Process S)")
    ax.set_xlim(0, 72)
    hour_ticks(ax, 0, 72, 6)
    ax.set_ylabel("áp lực ngủ")
    ax.set_title("Mô hình hai quá trình: S tăng khi thức, giảm khi ngủ, đổi trạng thái khi chạm ngưỡng")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.14), ncol=4)
    save(fig, "fig0a_two_process.png")

    # Hình 2: chim sơn ca và cú đêm trong cùng một ngày
    fig, axes = plt.subplots(2, 1, figsize=(9, 5), sharex=True, gridspec_kw={"height_ratios": [1, 2.2]})
    for k, (name, phi, color) in enumerate([("Chim sơn ca (phi = 15h)", 15.0, BLUE),
                                             ("Cú đêm (phi = 19h)", 19.0, ORANGE)]):
        q = p.with_(phi=phi)
        t, H, s = simulate_free(q, days=12)
        win = (t >= 10 * 24 + 12) & (t < 11 * 24 + 12)
        tt = t[win] - 10 * 24
        for on, off in sleep_episodes(tt, s[win]):
            axes[0].barh(k, off - on, left=on, height=0.5, color=color)
        A = np.where(s[win], np.nan, alertness(t[win], H[win], q))  # lúc ngủ thì không tính
        axes[1].plot(tt, A, color=color, label=name)
    axes[0].set_yticks([0, 1])
    axes[0].set_yticklabels(["sơn ca", "cú đêm"])
    axes[0].set_title("Giờ ngủ tự nhiên (không báo thức)")
    axes[0].grid(axis="y", visible=False)
    axes[1].axhline(0, color=INK2, lw=1)
    axes[1].set_ylabel("độ tỉnh táo A = H⁺(t) − H(t)")
    axes[1].set_title("Độ tỉnh táo trong ngày: cùng một giờ, hai người khác nhau")
    axes[1].legend(loc="upper center", bbox_to_anchor=(0.5, -0.12), ncol=2)
    axes[1].set_xlim(12, 36)
    hour_ticks(axes[1], 12, 36, 3)
    save(fig, "fig0b_lark_vs_owl.png")


if __name__ == "__main__":
    main()
