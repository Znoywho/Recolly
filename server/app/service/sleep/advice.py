"""Fixed sleep and study advice for the three animals, each line with its source.

The animals are a display layer, so this advice is general guidance, not a prescription.
Limits of the evidence behind it:
- Facer-Childs 2019: 22 healthy night owls (mean age 21), not people with a sleep disorder.
- Goldin 2020: Argentinian school students, not university students.
- Phillips 2017: a correlation in 61 undergraduates, so regular sleep is not proven to raise grades.
- Sleep Foundation: a general health article; the animal types are not a research classification.
"""

from dataclasses import dataclass

from app.service.sleep.chronotype import Animal


@dataclass(frozen=True)
class Source:
    citation: str
    url: str


@dataclass(frozen=True)
class Advice:
    text: str   # shown to the user, in Vietnamese
    source: Source


SLEEP_FOUNDATION = Source("Sleep Foundation, Chronotypes (2026)",
                          "https://www.sleepfoundation.org/how-sleep-works/chronotypes")
WATSON_2015 = Source("Watson et al. 2015, Sleep 38(6)",
                     "https://pmc.ncbi.nlm.nih.gov/articles/PMC4434546/")
PHILLIPS_2017 = Source("Phillips et al. 2017, Scientific Reports 7",
                       "https://doi.org/10.1038/s41598-017-03171-4")
FACER_CHILDS_2019 = Source("Facer-Childs et al. 2019, Sleep Medicine 60",
                           "https://doi.org/10.1016/j.sleep.2019.05.001")
GOLDIN_2020 = Source("Goldin et al. 2020, Nature Human Behaviour 4",
                     "https://doi.org/10.1038/s41562-020-0820-2")

COMMON_ADVICE = (
    Advice("Cố gắng ngủ ít nhất 7 tiếng mỗi đêm một cách đều đặn.", WATSON_2015),
    Advice("Giữ giờ ngủ và giờ dậy đều giữa các ngày. Ở sinh viên, ngủ thất thường đi kèm kết quả học tập thấp hơn.",
           PHILLIPS_2017),
)

ANIMAL_ADVICE = {
    Animal.LION: (
        Advice("Bạn thường làm việc hiệu quả nhất vào buổi sáng, nên ưu tiên việc khó vào buổi sáng.",
               SLEEP_FOUNDATION),
    ),
    Animal.BEAR: (
        Advice("Bạn thường hợp với giờ giấc hành chính, nên ưu tiên việc khó vào ban ngày.", SLEEP_FOUNDATION),
    ),
    Animal.WOLF: (
        Advice("Khi được chọn, hãy xếp việc khó vào buổi chiều hoặc buổi tối thay vì sáng sớm.", GOLDIN_2020),
        Advice("Nếu muốn dời nhịp sớm hơn, hãy thử ngủ và dậy sớm hơn 2–3 tiếng so với giờ quen, "
               "giữ giờ này cả ngày học lẫn ngày nghỉ.", FACER_CHILDS_2019),
        Advice("Ra ngoài trời nhiều vào buổi sáng, hạn chế ánh sáng buổi tối và không dùng caffeine sau 15h.",
               FACER_CHILDS_2019),
    ),
}


def advice_for(animal: Animal) -> list[Advice]:
    """Advice for one animal: its own lines first, then the lines shared by everyone."""
    return [*ANIMAL_ADVICE[animal], *COMMON_ADVICE]
