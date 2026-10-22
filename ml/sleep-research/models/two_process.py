"""Mô hình hai quá trình (two-process model, 2PM) của Borbély / Daan-Beersma-Borbély.

Theo phần Methods của Skeldon & Dijk (2025), xem mark/2.md:

    Thức:  dH/dt = (mu - H) / chi_w       -> H tăng dần về mu
    Ngủ:   dH/dt = (0  - H) / chi_s       -> H giảm dần về 0   (mu_s = 0)

    Ngưỡng trên  H+(t) = H0_plus  + a * C(t)   (đang thức, chạm ngưỡng này -> đi ngủ)
    Ngưỡng dưới  H-(t) = H0_minus + a * C(t)   (đang ngủ,  chạm ngưỡng này -> thức dậy)
    C(t) = cos(2*pi*(t - phi) / T)

`phi` là giờ trong ngày mà C(t) cao nhất (lúc khó ngủ nhất). Chronotype
chính là `phi`: người "cú đêm" có phi muộn hơn người "chim sơn ca".

Thời gian tính bằng giờ, t = 0 là 00:00 của ngày đầu tiên.
"""

from dataclasses import dataclass, replace

import numpy as np

DT = 5 / 60  # bước thời gian mặc định: 5 phút


@dataclass(frozen=True)
class Params:
    chi_s: float = 4.2      # hằng số thời gian khi ngủ (giờ)
    chi_w: float = 18.2     # hằng số thời gian khi thức (giờ)
    mu: float = 1.0         # tiệm cận trên của áp lực ngủ
    H0_plus: float = 0.67   # mức trung bình ngưỡng trên
    H0_minus: float = 0.17  # mức trung bình ngưỡng dưới
    a: float = 0.12         # biên độ nhịp ngày đêm
    period: float = 24.0    # chu kỳ nhịp ngày đêm (giờ)
    phi: float = 16.0       # giờ đỉnh của C(t) -> pha chronotype

    def with_(self, **kw):
        return replace(self, **kw)


def circadian(t, p: Params):
    return np.cos(2 * np.pi * (np.asarray(t) - p.phi) / p.period)


def upper_threshold(t, p: Params):
    return p.H0_plus + p.a * circadian(t, p)


def lower_threshold(t, p: Params):
    return p.H0_minus + p.a * circadian(t, p)


def natural_period(p: Params):
    """Phương trình (1)-(3) của Skeldon & Dijk khi a = 0 (không có nhịp ngày đêm)."""
    t_sleep = p.chi_s * np.log(p.H0_plus / p.H0_minus)
    t_wake = p.chi_w * np.log((p.mu - p.H0_minus) / (p.mu - p.H0_plus))
    return t_sleep, t_wake, t_sleep + t_wake


def step_H(H, asleep, p: Params, dt=DT):
    """Cập nhật chính xác (nghiệm giải tích) của H sau một bước dt."""
    decay_w = np.exp(-dt / p.chi_w)
    decay_s = np.exp(-dt / p.chi_s)
    return np.where(asleep, H * decay_s, p.mu + (H - p.mu) * decay_w)


def simulate_free(p: Params, days=10, dt=DT, H_init=0.5, asleep_init=False):
    """Ngủ/thức tự nhiên, quyết định hoàn toàn bởi hai ngưỡng (không có báo thức, lịch học)."""
    t = np.arange(0, days * 24, dt)
    H = np.empty_like(t)
    asleep = np.zeros(t.size, dtype=bool)
    h, s = H_init, asleep_init
    for i, ti in enumerate(t):
        H[i], asleep[i] = h, s
        if not s and h >= upper_threshold(ti, p):
            s = True
        elif s and h <= lower_threshold(ti, p):
            s = False
        h = step_H(h, s, p, dt)
    return t, H, asleep


def simulate_forced(sleep_mask, p: Params, dt=DT, H_init=0.5):
    """Tính H khi lịch ngủ đã biết trước (quan sát được), không dùng ngưỡng.

    Đây là cách dùng mô hình trong ứng dụng: ta biết người dùng ngủ lúc nào
    (suy ra từ màn hình) và muốn biết áp lực ngủ / độ tỉnh táo của họ.
    `p.chi_w` có thể là mảng numpy để mô phỏng nhiều bộ tham số cùng lúc.
    """
    H = np.empty((len(sleep_mask),) + np.shape(p.chi_w))
    h = np.full(np.shape(p.chi_w), H_init, dtype=float)
    for i, s in enumerate(sleep_mask):
        H[i] = h
        h = step_H(h, s, p, dt)
    return H


def alertness(t, H, p: Params):
    """Độ tỉnh táo = khoảng cách từ áp lực ngủ hiện tại tới ngưỡng ngủ.

    A lớn  -> còn xa ngưỡng ngủ -> tỉnh táo.
    A <= 0 -> mô hình cho rằng người này "lẽ ra đã ngủ" (đang cố thức).
    """
    return upper_threshold(t, p) - H


def sleep_episodes(t, asleep):
    """Trả về danh sách (giờ bắt đầu ngủ, giờ thức dậy) từ mảng bool."""
    a = np.asarray(asleep, dtype=int)
    starts = np.flatnonzero(np.diff(a) == 1) + 1
    ends = np.flatnonzero(np.diff(a) == -1) + 1
    if a[0]:
        starts = np.r_[0, starts]
    if a[-1]:
        ends = np.r_[ends, a.size - 1]
    return [(t[s], t[e]) for s, e in zip(starts, ends)]


def mean_mid_sleep(p: Params, days=20, burn_in=10):
    """Giờ giữa giấc ngủ (mid-sleep) trung bình khi ngủ tự nhiên với bộ tham số p."""
    t, _, asleep = simulate_free(p, days=days)
    mids = [(on + off) / 2 for on, off in sleep_episodes(t, asleep)
            if on >= burn_in * 24 and off < t[-1]]  # bỏ giấc ngủ bị cắt ở cuối
    return circular_mean_hours(np.array(mids) % 24)


def phi_from_mid_sleep(mid_sleep, p: Params = Params()):
    """Đổi giờ giữa giấc ngủ (vd. MSFsc từ MCTQ) thành pha phi của mô hình.

    Mô hình bất biến khi dịch thời gian: dịch phi bao nhiêu thì giấc ngủ dịch
    bấy nhiêu. Nên chỉ cần mô phỏng một lần để biết độ lệch giữa phi và mid-sleep.
    """
    offset = p.phi - mean_mid_sleep(p)
    return (mid_sleep + offset) % 24


def circular_mean_hours(h):
    ang = np.asarray(h) * 2 * np.pi / 24
    return (np.arctan2(np.sin(ang).mean(), np.cos(ang).mean()) * 24 / (2 * np.pi)) % 24


def circular_diff_hours(a, b):
    """a - b trên đồng hồ 24h, kết quả nằm trong [-12, 12)."""
    return (np.asarray(a) - np.asarray(b) + 12) % 24 - 12
