# CP-SAT: giờ vàng và mức tập trung (S1, R24–R27)

Code: `app/service/scheduler.py` · giờ vàng: `app/service/sleep/timeline.py` (`Timeline.windows`)

## Một định nghĩa giờ vàng duy nhất

Mỗi ngày, `Timeline.windows(day)` lấy KSS dự đoán của các bước 5 phút lúc đang thức, rồi chia thành:
- **golden**: KSS ≤ phân vị 25% của ngày, liên tục ≥ 30 phút, không nằm trong 30 phút đầu sau khi thức (quán tính ngủ);
- **low**: KSS ≥ phân vị 75% của ngày, liên tục ≥ 30 phút;
- **normal**: phần thời gian thức còn lại.

Màn Biorhythm và CP-SAT dùng **chung** hàm này. Một slot 15 phút thuộc tầng `golden`/`low` khi nằm trọn trong cửa sổ đó.

## Mức tập trung của todo

| Mức | `difficulty` | Mặc định theo category |
|---|---|---|
| `high` – cần tập trung cao | ≥ 4 (app lưu 5) | `exam`, `assignment` |
| `normal` – bình thường | 2–3 (app lưu 3) | `study` |
| `light` – việc nhẹ | 1 | `personal`, `other` |

Khi app gửi `difficulty = null` lúc tạo todo, server điền giá trị mặc định ở trên (`DEFAULT_DIFFICULTY`).
**Bảng ánh xạ category → mức là giả định của team, chưa có số liệu kiểm chứng.**

## Hàm mục tiêu (mỗi slot của một khối học)

```
cost = TIER_COST[focus][tier] + KSS × 100 + start_slot // 4
```

| focus \ tier | golden | normal | low |
|---|---|---|---|
| high | 0 | 1000 | 2000 |
| normal | 0 | 0 | 1000 |
| light | 1000 | 300 | 0 |

- `TIER_COST` lớn hơn mọi chênh lệch KSS (KSS × 100 ≤ 900), nên khối học chỉ rời tầng ưu tiên khi tầng đó hết chỗ.
  Trong cùng một tầng, slot có KSS thấp hơn (tỉnh hơn) được chọn.
- Bài `normal` không có ưu tiên giữa golden và normal. Khi bài `high` cần giờ vàng, solver nhường chỗ vì
  đẩy bài `high` ra ngoài giờ vàng tốn 1000/slot.
- Mỗi khối học trả về `focus` và `window`. Nếu `focus = high` mà `window ≠ golden` thì giờ vàng đã kín
  (lịch học, giờ bận, hoặc bài khác), và app nên giải thích điều này cho người dùng.

Các hằng số 1000/300/2000 là **giả định của team** để thể hiện thứ tự ưu tiên, không đến từ tài liệu nghiên cứu.

## Nghiên cứu còn mở

- Lập luận "việc cần nhiều nhận thức nhạy hơn với nhịp sinh học" thường dẫn từ Schmidt, Collette, Cajochen & Peigneux (2007),
  *A time to think: circadian rhythms in human cognition*, Cognitive Neuropsychology. **Chưa đọc full text.**
- `KSS = 7.5 − 9·A` và bảng quyết định mô hình giấc ngủ: xem [`docs/sleep-model.md`](../../docs/sleep-model.md). Phần này chưa được chốt.
- Về sau: cho người dùng đánh giá "khó hơn / đúng / dễ hơn" sau mỗi khối học để điều chỉnh mặc định và kiểm chứng giờ vàng.
