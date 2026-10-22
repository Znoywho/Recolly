"""Cá nhân hóa mô hình hai quá trình bằng suy luận Bayes (ý tưởng của Van Dongen et al. 2007, mark/1.md).

Mỗi người có các tham số "tính cách" (trait) riêng mà ta không biết trước:
    phi    pha nhịp ngày đêm (chronotype)
    chi_w  tốc độ tích áp lực ngủ khi thức (người nhạy/kém nhạy với thiếu ngủ)

Quy trình:
    1. Prior: niềm tin ban đầu. Hoặc theo quần thể (ai cũng như nhau), hoặc theo
       bảng hỏi MCTQ của chính người đó (prior chronotype).
    2. Mỗi ngày người dùng báo vài điểm KSS -> tính likelihood cho từng bộ tham số.
    3. Posterior ∝ prior x likelihood -> dự báo KSS kèm khoảng tin cậy 95%.
Càng nhiều ngày dữ liệu thì posterior càng hẹp và dự báo càng chính xác.

Dùng lưới (grid) thay cho MCMC: chỉ có 2 tham số nên lưới vừa nhanh vừa dễ hiểu.
Lưu ý: H không phụ thuộc phi, nên chỉ cần mô phỏng H theo chi_w rồi ghép phi vào sau.
"""

import numpy as np

from .synthetic import KSS_BETA0, KSS_BETA1, KSS_SIGMA
from .two_process import Params, circular_diff_hours, simulate_forced

PHI_GRID = np.arange(0, 24, 0.25)
CHI_GRID = np.arange(12, 26.01, 0.5)
OBS_SIGMA = np.sqrt(KSS_SIGMA ** 2 + 1 / 12)  # nhiễu + sai số do làm tròn điểm KSS


class BayesIndividual:
    def __init__(self, t, sleep_mask, phi_prior_mean, phi_prior_sd,
                 chi_prior_mean=18.2, chi_prior_sd=2.5, base: Params = Params()):
        self.t = t
        self.base = base
        H = simulate_forced(sleep_mask, base.with_(chi_w=CHI_GRID))  # (thời gian, chi)
        self.H = H
        d_phi = circular_diff_hours(PHI_GRID, phi_prior_mean)
        log_prior_phi = -0.5 * (d_phi / phi_prior_sd) ** 2
        log_prior_chi = -0.5 * ((CHI_GRID - chi_prior_mean) / chi_prior_sd) ** 2
        self.log_prior = log_prior_phi[:, None] + log_prior_chi[None, :]
        self.log_post = self.log_prior.copy()

    def predicted_kss_grid(self, idx):
        """KSS dự báo cho mọi bộ (phi, chi_w): mảng (len(idx), phi, chi)."""
        idx = np.atleast_1d(idx)
        C = np.cos(2 * np.pi * (self.t[idx, None] - PHI_GRID[None, :]) / self.base.period)
        upper = self.base.H0_plus + self.base.a * C                  # (obs, phi)
        A = upper[:, :, None] - self.H[idx][:, None, :]              # (obs, phi, chi)
        return KSS_BETA0 - KSS_BETA1 * A

    def update(self, idx, kss):
        """Cập nhật posterior với các quan sát KSS tại các vị trí idx."""
        self.log_post = self.log_prior.copy()
        if len(idx):
            resid = np.asarray(kss)[:, None, None] - self.predicted_kss_grid(idx)
            self.log_post += (-0.5 * (resid / OBS_SIGMA) ** 2).sum(axis=0)
        return self

    @property
    def weights(self):
        w = np.exp(self.log_post - self.log_post.max())
        return w / w.sum()

    def summary(self):
        w = self.weights
        w_phi, w_chi = w.sum(axis=1), w.sum(axis=0)
        ang = PHI_GRID * 2 * np.pi / 24
        phi_mean = np.arctan2((w_phi * np.sin(ang)).sum(), (w_phi * np.cos(ang)).sum()) * 24 / (2 * np.pi)
        phi_sd = np.sqrt((w_phi * circular_diff_hours(PHI_GRID, phi_mean) ** 2).sum())
        chi_mean = (w_chi * CHI_GRID).sum()
        chi_sd = np.sqrt((w_chi * (CHI_GRID - chi_mean) ** 2).sum())
        return {"phi": phi_mean % 24, "phi_sd": phi_sd, "chi_w": chi_mean, "chi_w_sd": chi_sd}

    def predict(self, idx, n_samples=2000, rng=None):
        """Trung bình và khoảng dự báo 95% của KSS tại các vị trí idx."""
        rng = np.random.default_rng(0) if rng is None else rng
        w = self.weights.ravel()
        pred = self.predicted_kss_grid(idx).reshape(len(np.atleast_1d(idx)), -1)
        mean = pred @ w
        pick = rng.choice(w.size, n_samples, p=w)
        draws = pred[:, pick] + rng.normal(0, OBS_SIGMA, (pred.shape[0], n_samples))
        lo, hi = np.percentile(draws, [2.5, 97.5], axis=1)
        return mean, lo, hi


def fixed_param_kss(t, sleep_mask, idx, phi, chi_w=18.2, base: Params = Params()):
    """Dự báo KSS với một bộ tham số cố định (mô hình chung / chỉ chỉnh chronotype)."""
    p = base.with_(phi=phi, chi_w=chi_w)
    H = simulate_forced(sleep_mask, p)
    C = np.cos(2 * np.pi * (t[idx] - phi) / p.period)
    A = p.H0_plus + p.a * C - H[idx]
    return KSS_BETA0 - KSS_BETA1 * A
