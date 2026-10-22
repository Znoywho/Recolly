"""Suy ra giờ ngủ/thức từ dữ liệu bật màn hình điện thoại.

Đây là bài toán "sự kiện ẩn" giống slide của Dietterich (mark/3.md): ta không
thấy được lúc nào người dùng ngủ, chỉ thấy gián tiếp qua việc họ dùng điện thoại.

Đầu vào: mảng bool `screen` theo từng ô 5 phút (True = có bật màn hình).
Với dữ liệu thật (StudentLife, app Android), ta đổi các sự kiện
ACTION_SCREEN_ON/OFF thành dạng này.

Hai cách:
  1. heuristic_sleep: khoảng tắt màn hình dài nhất mỗi đêm. Đơn giản, nhưng hỏng
     khi người dùng thức giấc giữa đêm xem điện thoại (khoảng tắt bị cắt đôi).
  2. hmm_sleep: Hidden Markov Model 2 trạng thái {thức, ngủ}. Xác suất chuyển
     trạng thái thay đổi theo giờ trong ngày, lấy từ chronotype (phi) của người
     dùng, nên vài lần bật máy giữa đêm không làm "đứt" giấc ngủ.
"""

import numpy as np

from .two_process import DT, Params, circular_diff_hours, simulate_free, sleep_episodes


def runs(mask):
    """Các đoạn liên tiếp True: danh sách (vị trí đầu, vị trí sau cuối)."""
    m = np.r_[False, np.asarray(mask, dtype=bool), False]
    d = np.diff(m.astype(int))
    return list(zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)))


def nightly_main_sleep(t, sleep_mask, min_hours=2.0):
    """Mỗi đêm (12h trưa hôm trước -> 12h trưa hôm sau) lấy giấc ngủ dài nhất.

    Trả về dict: chỉ số đêm -> (giờ ngủ, giờ thức) tính theo giờ tuyệt đối.
    """
    out = {}
    for s, e in runs(sleep_mask):
        if (e - s) * DT < min_hours:
            continue
        night = int((t[s] - 12) // 24)
        if night not in out or (e - s) * DT > out[night][1] - out[night][0]:
            out[night] = (t[s], t[min(e, t.size - 1)])
    return out


def heuristic_sleep(t, screen, min_hours=3.0):
    """Cách 1: khoảng tắt màn hình dài nhất mỗi đêm là giấc ngủ."""
    mask = np.zeros(t.size, dtype=bool)
    best = {}
    for s, e in runs(~np.asarray(screen)):
        if (e - s) * DT < min_hours:
            continue
        mid_night = int((t[s] - 12) // 24)
        if mid_night not in best or e - s > best[mid_night][1] - best[mid_night][0]:
            best[mid_night] = (s, e)
    for s, e in best.values():
        mask[s:e] = True
    return mask


def typical_sleep_window(phi, p: Params = Params()):
    """Giờ ngủ và giờ thức "tự nhiên" của người có pha phi (mô phỏng 2PM không báo thức)."""
    t, _, asleep = simulate_free(p.with_(phi=phi), days=14)
    eps = [(on % 24, off % 24) for on, off in sleep_episodes(t, asleep)
           if on >= 7 * 24 and off < t[-1]]
    on = np.angle(np.mean(np.exp(1j * np.array([e[0] for e in eps]) * np.pi / 12))) * 12 / np.pi
    off = np.angle(np.mean(np.exp(1j * np.array([e[1] for e in eps]) * np.pi / 12))) * 12 / np.pi
    return on % 24, off % 24


def _bump(tod, center, width):
    d = circular_diff_hours(tod, center)
    return np.exp(-0.5 * (d / width) ** 2)


def hmm_sleep(t, screen, phi, p_on_sleep=0.01, p_on_wake=None,
              onset_width=2.0, wake_width=2.5, return_posterior=False):
    """Cách 2: HMM với xác suất chuyển trạng thái phụ thuộc chronotype.

    Trạng thái 0 = thức, 1 = ngủ.
    Phát xạ (emission): P(bật màn hình | thức) = p_on_wake, P(bật | ngủ) = p_on_sleep.
    Chuyển trạng thái tại giờ t:
        P(thức -> ngủ) cao quanh giờ ngủ quen thuộc của chronotype phi
        P(ngủ -> thức) cao quanh giờ thức quen thuộc
    Thuật toán forward-backward cho xác suất hậu nghiệm P(ngủ | toàn bộ dữ liệu).
    """
    screen = np.asarray(screen, dtype=bool)
    tod = t % 24
    if p_on_wake is None:
        day = (tod >= 10) & (tod < 20)  # ước lượng mức dùng máy lúc thức từ ban ngày
        p_on_wake = float(np.clip(screen[day].mean(), 0.05, 0.95))
    on_h, off_h = typical_sleep_window(phi)
    p_ws = 0.0005 + 0.05 * _bump(tod, on_h, onset_width)
    p_sw = 0.0005 + 0.05 * _bump(tod, off_h, wake_width)

    emit = np.where(screen[:, None], [p_on_wake, p_on_sleep], [1 - p_on_wake, 1 - p_on_sleep])
    n = t.size
    alpha = np.empty((n, 2))
    a = np.array([0.5, 0.5]) * emit[0]
    alpha[0] = a / a.sum()
    for i in range(1, n):
        prev = alpha[i - 1]
        a = np.array([prev[0] * (1 - p_ws[i]) + prev[1] * p_sw[i],
                      prev[0] * p_ws[i] + prev[1] * (1 - p_sw[i])]) * emit[i]
        alpha[i] = a / a.sum()
    beta = np.ones((n, 2))
    for i in range(n - 2, -1, -1):
        b = emit[i + 1] * beta[i + 1]
        bb = np.array([(1 - p_ws[i + 1]) * b[0] + p_ws[i + 1] * b[1],
                       p_sw[i + 1] * b[0] + (1 - p_sw[i + 1]) * b[1]])
        beta[i] = bb / bb.sum()
    post = alpha * beta
    post = post[:, 1] / post.sum(axis=1)
    mask = post > 0.5
    return (mask, post) if return_posterior else mask


def episode_errors(t, true_mask, est_mask):
    """Sai số (phút) giờ ngủ và giờ thức của giấc ngủ chính mỗi đêm."""
    truth = nightly_main_sleep(t, true_mask)
    est = nightly_main_sleep(t, est_mask)
    on_err, off_err, missed = [], [], 0
    for night, (on, off) in truth.items():
        if night not in est:
            missed += 1
            continue
        on_err.append((est[night][0] - on) * 60)
        off_err.append((est[night][1] - off) * 60)
    return np.array(on_err), np.array(off_err), missed
