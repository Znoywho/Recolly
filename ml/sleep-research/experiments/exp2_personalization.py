"""Thí nghiệm 2: mô hình cá nhân hóa có dự báo độ buồn ngủ (KSS) tốt hơn không?

Theo tinh thần Van Dongen et al. (2007): cho mô hình xem d ngày dữ liệu KSS rồi
dự báo KSS trên một tập kiểm tra cố định (7 ngày cuối, mô hình chưa từng thấy).
Tăng dần d và xem sai số giảm ra sao.

Bốn mô hình:
  (a) Chung:        phi = trung bình quần thể, chi_w = 18.2 (mọi người như nhau)
  (b) Chronotype:   phi lấy từ MCTQ, chi_w = 18.2
  (c) Bayes:        prior quần thể, cập nhật bằng KSS
  (d) Bayes + MCTQ: prior từ MCTQ, cập nhật bằng KSS
Mốc tham chiếu: "biết tham số thật" (tốt nhất có thể với nguồn giấc ngủ đó).

Mỗi mô hình chạy với hai nguồn giấc ngủ:
  - giấc ngủ thật (coi như đo bằng smartwatch / nhật ký chính xác)
  - giấc ngủ suy ra từ màn hình bằng HMM (thí nghiệm 1)

Chạy: .venv/bin/python -m experiments.exp2_personalization
"""

import numpy as np

from experiments.common import AQUA, BLUE, INK2, ORANGE, YELLOW, cohort, plt, save
from models.bayes_individual import BayesIndividual, fixed_param_kss
from models.chronotype import score_mctq
from models.screen_sleep import hmm_sleep
from models.two_process import circular_diff_hours, phi_from_mid_sleep

POP_PHI, POP_PHI_SD = 17.4, 1.5
MCTQ_PHI_SD = 1.0
BURN_IN_DAYS = 2   # 2 ngày đầu chỉ để H "ổn định" (không biết áp lực ngủ ban đầu)
TEST_DAYS = 7      # tập kiểm tra: 7 ngày cuối
D = np.array([0, 1, 2, 3, 5, 7, 10, 14])
MODELS = ["(a) Chung", "(b) Chronotype", "(c) Bayes", "(d) Bayes + MCTQ"]
ORACLE = "biết tham số thật"
COLORS = dict(zip(MODELS, [INK2, YELLOW, ORANGE, BLUE]))
SOURCES = ["giấc ngủ thật", "giấc ngủ từ màn hình (HMM)"]


def evaluate(st, mask, phi_mctq):
    """Trả về sai số bình phương TB, độ phủ, sai số tham số cho mọi mô hình và mọi d."""
    obs_t = st.t[st.kss_idx]
    test = obs_t >= st.t[-1] - TEST_DAYS * 24
    idx, y = st.kss_idx[test], st.kss[test]
    out = {"sq": {}, "cov": {}, "phi": {}, "chi": {}}

    fixed = {"(a) Chung": (POP_PHI, 18.2), "(b) Chronotype": (phi_mctq, 18.2),
             ORACLE: (st.params.phi, st.params.chi_w)}
    for m, (phi, chi) in fixed.items():
        err = ((fixed_param_kss(st.t, mask, idx, phi, chi) - y) ** 2).mean()
        out["sq"][m] = np.full(D.size, err)  # không học nên không đổi theo d

    priors = {"(c) Bayes": (POP_PHI, POP_PHI_SD), "(d) Bayes + MCTQ": (phi_mctq, MCTQ_PHI_SD)}
    for m, (mean, sd) in priors.items():
        b = BayesIndividual(st.t, mask, mean, sd)
        sq, cov, phi_e, chi_e = [], [], [], []
        for d in D:
            train = (obs_t >= BURN_IN_DAYS * 24) & (obs_t < (BURN_IN_DAYS + d) * 24)
            b.update(st.kss_idx[train], st.kss[train])
            pred, lo, hi = b.predict(idx)
            s = b.summary()
            sq.append(((pred - y) ** 2).mean())
            cov.append(((y >= lo) & (y <= hi)).mean())
            phi_e.append(abs(circular_diff_hours(s["phi"], st.params.phi)))
            chi_e.append(abs(s["chi_w"] - st.params.chi_w))
        out["sq"][m], out["cov"][m] = np.array(sq), np.array(cov)
        out["phi"][m], out["chi"][m] = np.array(phi_e), np.array(chi_e)
    return out


def main():
    students, _ = cohort()
    res = {src: [] for src in SOURCES}
    for st in students:
        phi_mctq = phi_from_mid_sleep(score_mctq(st.mctq).MSFsc)
        res[SOURCES[0]].append(evaluate(st, st.asleep, phi_mctq))
        res[SOURCES[1]].append(evaluate(st, hmm_sleep(st.t, st.screen, phi_mctq), phi_mctq))

    def avg(src, key, m, rmse=False):
        v = np.mean([r[key][m] for r in res[src]], axis=0)
        return np.sqrt(v) if rmse else v

    for src in SOURCES:
        print(f"=== Nguồn giấc ngủ: {src} ===")
        print("RMSE dự báo KSS trên 7 ngày kiểm tra, theo số ngày dữ liệu đã thấy (d):")
        print("   " + f"{'mô hình':<20}" + "".join(f"{f'd={d}':>8}" for d in D))
        for m in MODELS + [ORACLE]:
            print("   " + f"{m:<20}" + "".join(f"{v:>8.2f}" for v in avg(src, "sq", m, rmse=True)))
        print("Độ phủ khoảng dự báo 95% (lý tưởng 0.95) | sai số phi (phút) | sai số chi_w (giờ), tại d = 0 / 14:")
        for m in MODELS[2:]:
            c, p, x = avg(src, "cov", m), avg(src, "phi", m) * 60, avg(src, "chi", m)
            print(f"   {m:<20} {c[0]:.2f} / {c[-1]:.2f}  |  {p[0]:5.1f} / {p[-1]:5.1f}  |  {x[0]:.2f} / {x[-1]:.2f}")

    # Hình 1: RMSE theo số ngày, hai nguồn giấc ngủ
    fig, axes = plt.subplots(1, 2, figsize=(10, 4), sharey=True)
    for ax, src in zip(axes, SOURCES):
        for m in MODELS:
            ax.plot(D, avg(src, "sq", m, rmse=True), color=COLORS[m], marker="o", ms=4, label=m)
        ax.plot(D, avg(src, "sq", ORACLE, rmse=True), color=AQUA, ls="--", label=ORACLE)
        ax.set_title(src)
        ax.set_xlabel("số ngày dữ liệu KSS mô hình đã thấy")
        ax.set_xticks(D)
    axes[0].set_ylabel("RMSE dự báo KSS (7 ngày kiểm tra)")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=5, bbox_to_anchor=(0.5, -0.1))
    fig.suptitle("Cá nhân hóa giúp dự báo tốt dần lên theo từng ngày", fontweight="bold", y=1.03)
    save(fig, "fig2a_rmse_vs_days.png")

    # Hình 2: tham số học được hội tụ về giá trị thật (nguồn: giấc ngủ thật)
    src = SOURCES[0]
    fig, axes = plt.subplots(1, 2, figsize=(10, 3.6))
    for m in MODELS[2:]:
        axes[0].plot(D, avg(src, "phi", m) * 60, color=COLORS[m], marker="o", ms=4, label=m)
        axes[1].plot(D, avg(src, "chi", m), color=COLORS[m], marker="o", ms=4, label=m)
    axes[0].set_title("Sai số chronotype phi (phút)")
    axes[1].set_title("Sai số tốc độ tích áp lực ngủ chi_w (giờ)")
    for ax in axes:
        ax.set_xlabel("số ngày dữ liệu")
        ax.set_xticks(D)
        ax.set_ylim(bottom=0)
    axes[1].legend()
    fig.suptitle("Tham số học được tiến dần về giá trị thật (nguồn: giấc ngủ thật, 40 sinh viên)",
                 fontweight="bold", y=1.03)
    save(fig, "fig2b_parameter_convergence.png")


if __name__ == "__main__":
    main()
