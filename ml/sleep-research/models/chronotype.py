"""Tính chronotype từ bảng hỏi.

MCTQ (Munich Chronotype Questionnaire, Roenneberg et al. 2003, 2012):
người dùng khai giờ ngủ (sleep onset) và giờ thức (sleep end) trong ngày đi học
và ngày nghỉ. Bản đầy đủ còn hỏi giờ lên giường, thời gian để ngủ được (latency)...
ở đây rút gọn thành hai mốc để dễ hiểu.

    SD   = thời lượng ngủ,  MS = giờ giữa giấc ngủ (mid-sleep)
    SDweek = (SDw * WD + SDf * (7 - WD)) / 7               (trung bình cả tuần)
    MSFsc  = MSF - (SDf - SDweek) / 2   nếu SDf > SDw       (bỏ phần ngủ bù cuối tuần)
    SJL    = |MSF - MSW|                                     (social jetlag)

MSFsc là "chronotype" dưới dạng một giờ cụ thể, nên đưa thẳng vào phi của mô hình
qua `two_process.phi_from_mid_sleep`.
"""

from dataclasses import dataclass

from .two_process import circular_diff_hours


@dataclass
class MCTQAnswers:
    sleep_onset_work: float   # giờ ngủ ngày đi học, vd. 23.5 = 23:30, 0.75 = 00:45
    sleep_end_work: float     # giờ thức ngày đi học
    sleep_onset_free: float
    sleep_end_free: float
    work_days: int = 5        # số ngày đi học mỗi tuần


@dataclass
class MCTQResult:
    SDw: float
    SDf: float
    MSW: float
    MSF: float
    SDweek: float
    MSFsc: float
    SJL: float

    @property
    def label(self):
        return chronotype_label(self.MSFsc)


def _duration(onset, end):
    return (end - onset) % 24


def score_mctq(ans: MCTQAnswers) -> MCTQResult:
    SDw = _duration(ans.sleep_onset_work, ans.sleep_end_work)
    SDf = _duration(ans.sleep_onset_free, ans.sleep_end_free)
    MSW = (ans.sleep_onset_work + SDw / 2) % 24
    MSF = (ans.sleep_onset_free + SDf / 2) % 24
    SDweek = (SDw * ans.work_days + SDf * (7 - ans.work_days)) / 7
    MSFsc = (MSF - (SDf - SDweek) / 2) % 24 if SDf > SDw else MSF
    SJL = abs(circular_diff_hours(MSF, MSW))
    return MCTQResult(SDw, SDf, MSW, MSF, SDweek, MSFsc, SJL)


def chronotype_label(msfsc):
    """Nhãn minh họa. Các mốc chỉ để đọc kết quả, không phải tiêu chuẩn chẩn đoán."""
    h = msfsc - 24 if msfsc > 12 else msfsc  # 23:30 -> -0.5 (rất sớm)
    if h < 3:
        return "sớm (chim sơn ca)"
    if h < 4.5:
        return "hơi sớm"
    if h < 5.5:
        return "trung gian"
    if h < 6.5:
        return "hơi muộn"
    return "muộn (cú đêm)"


def rmeq_category(total_score: int):
    """rMEQ 5 câu (Adan & Almirall 1991), tổng điểm 4-25."""
    if not 4 <= total_score <= 25:
        raise ValueError("Tổng điểm rMEQ phải nằm trong 4..25")
    if total_score >= 22:
        return "chắc chắn buổi sáng"
    if total_score >= 18:
        return "hơi buổi sáng"
    if total_score >= 12:
        return "trung gian"
    if total_score >= 8:
        return "hơi buổi tối"
    return "chắc chắn buổi tối"
