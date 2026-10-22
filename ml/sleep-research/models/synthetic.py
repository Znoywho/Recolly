"""Sinh "sinh viên ảo" để thử nghiệm khi chưa có dữ liệu thật.

Vì sao cần dữ liệu giả lập? Với dữ liệu thật ta không biết chronotype thật hay
nợ ngủ thật của người dùng, nên không đo được mô hình đúng tới đâu. Với dữ liệu
giả lập ta biết "đáp án" và kiểm tra được thuật toán có tìm lại đúng nó không.
Sau đó mới chạy trên dataset thật (StudentLife...).

Mỗi sinh viên có:
  - tính cách (trait): pha chronotype phi, tốc độ tích áp lực ngủ chi_w,
    thói quen lướt điện thoại trước khi ngủ (trì hoãn đi ngủ), mức dùng máy ban ngày
  - thời khóa biểu: ngày có tiết sáng thì phải đặt báo thức
Hành vi sinh ra: giờ ngủ/thức thật, dữ liệu bật màn hình theo từng 5 phút,
điểm buồn ngủ KSS tự báo cáo 4 lần/ngày và câu trả lời MCTQ (có sai số).
"""

from dataclasses import dataclass, field

import numpy as np

from .chronotype import MCTQAnswers
from .two_process import (DT, Params, alertness, circular_mean_hours, lower_threshold,
                          sleep_episodes, step_H, upper_threshold)

# Thời khóa biểu mẫu: thứ (0 = thứ Hai) -> danh sách tiết (bắt đầu, kết thúc)
DEFAULT_TIMETABLE = {
    0: [(7.0, 9.5), (13.0, 15.5)],
    1: [(9.5, 12.0)],
    2: [(7.0, 11.5)],
    3: [(13.0, 17.0)],
    4: [(7.0, 9.5)],
    5: [],
    6: [],
}

# Liên hệ giữa độ tỉnh táo của mô hình và điểm KSS (1 = rất tỉnh, 9 = rất buồn ngủ)
KSS_BETA0 = 7.5
KSS_BETA1 = 9.0
KSS_SIGMA = 0.7


def kss_from_alertness(A):
    return KSS_BETA0 - KSS_BETA1 * np.asarray(A)


@dataclass
class Student:
    params: Params
    procrastination_mean: float      # phút lướt máy trung bình trước khi ngủ
    phone_rate: float                # xác suất bật màn hình mỗi 5 phút lúc thức
    timetable: dict
    t: np.ndarray = field(repr=False)
    asleep: np.ndarray = field(repr=False)
    H: np.ndarray = field(repr=False)
    screen: np.ndarray = field(repr=False)   # bool: có bật màn hình trong ô 5 phút này
    kss_idx: np.ndarray = field(repr=False)  # vị trí các lần trả lời KSS
    kss: np.ndarray = field(repr=False)
    mctq: MCTQAnswers = None


def in_class(tod, weekday, timetable):
    return any(s <= tod < e for s, e in timetable.get(weekday, []))


def first_class(weekday, timetable):
    sessions = timetable.get(weekday, [])
    return min(s for s, _ in sessions) if sessions else None


def make_student(rng, days=28, phi=None, chi_w=None, procrastination_mean=None,
                 phone_rate=None, timetable=None, mctq_noise=0.5, night_check=0.008):
    """Mô phỏng một sinh viên trong `days` ngày (ngày 0 là thứ Hai)."""
    timetable = DEFAULT_TIMETABLE if timetable is None else timetable
    p = Params(
        phi=rng.normal(17.4, 1.2) if phi is None else phi,
        chi_w=float(np.clip(rng.normal(18.2, 2.0), 13, 25)) if chi_w is None else chi_w,
    )
    proc_mean = rng.uniform(0, 60) if procrastination_mean is None else procrastination_mean
    phone_rate = rng.uniform(0.2, 0.45) if phone_rate is None else phone_rate

    t = np.arange(0, days * 24, DT)
    n = t.size
    H = np.empty(n)
    asleep = np.zeros(n, dtype=bool)
    screen = np.zeros(n, dtype=bool)
    procrastinating = np.zeros(n, dtype=bool)

    h, s, delay_left = 0.5, False, None
    for i, ti in enumerate(t):
        tod, wd = ti % 24, int(ti // 24) % 7
        H[i], asleep[i] = h, s
        if not s:
            if delay_left is not None:
                procrastinating[i] = True
                delay_left -= DT
                if delay_left <= 0:
                    s, delay_left = True, None
            elif h >= upper_threshold(ti, p) and not 8 <= tod < 20:
                # Đủ buồn ngủ, nhưng còn lướt điện thoại thêm một lúc
                delay_left = rng.exponential(proc_mean / 60) if proc_mean > 0 else 0
        else:
            alarm = first_class(wd, timetable)
            alarm = None if alarm is None else alarm - 1.0
            if h <= lower_threshold(ti, p):
                s = False
            elif alarm is not None and abs(tod - alarm) < DT / 2:
                s = False  # bị báo thức đánh thức
        h = step_H(h, s, p)

        if asleep[i]:
            screen[i] = rng.random() < night_check  # thỉnh thoảng thức giấc xem điện thoại
        elif procrastinating[i]:
            screen[i] = rng.random() < 0.9
        elif in_class(tod, wd, timetable):
            screen[i] = rng.random() < 0.08
        else:
            screen[i] = rng.random() < phone_rate

    # KSS: 4 lần/ngày, vào lúc đang thức, trong khoảng 8h-23h
    A = alertness(t, H, p)
    kss_idx = []
    for d in range(days):
        day_mask = (t >= d * 24 + 8) & (t < d * 24 + 23) & ~asleep
        cand = np.flatnonzero(day_mask)
        if cand.size >= 4:
            kss_idx.extend(np.sort(rng.choice(cand, 4, replace=False)))
    kss_idx = np.array(kss_idx)
    kss = np.clip(np.round(kss_from_alertness(A[kss_idx]) + rng.normal(0, KSS_SIGMA, kss_idx.size)), 1, 9)

    st = Student(p, proc_mean, phone_rate, timetable, t, asleep, H, screen, kss_idx, kss)
    # Câu trả lời MCTQ = thói quen thật 2 tuần cuối + sai số khi tự nhớ lại
    st.mctq = mctq_from_sleep(t, asleep, timetable, last_days=14, rng=rng, noise_h=mctq_noise)
    return st


def mctq_from_sleep(t, asleep, timetable, last_days=14, rng=None, noise_h=0.0):
    """Điền MCTQ từ lịch ngủ (thật hoặc suy ra từ màn hình).

    Đêm "đi học" là đêm mà sáng hôm sau có tiết; còn lại là đêm "ngày nghỉ".
    """
    work_on, work_off, free_on, free_off = [], [], [], []
    for on, off in sleep_episodes(t, asleep):
        if off - on < 3 or on < t[-1] - last_days * 24 or off >= t[-1]:
            continue
        wake_day = int(off // 24) % 7
        is_work = first_class(wake_day, timetable) is not None
        (work_on if is_work else free_on).append(on % 24)
        (work_off if is_work else free_off).append(off % 24)

    def report(xs):
        noise = rng.normal(0, noise_h) if noise_h > 0 else 0.0
        return (circular_mean_hours(xs) + noise) % 24

    work_days = sum(1 for wd in range(7) if timetable.get(wd))
    return MCTQAnswers(report(work_on), report(work_off), report(free_on), report(free_off), work_days)
