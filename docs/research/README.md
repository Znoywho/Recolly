# Nghiên cứu Module 2: nhịp sinh học và chronotype

Tài liệu nền cho Module 2 (sleep debt, nhịp sinh học) của Recolly. Code chạy thật nằm ở `server/app/service/sleep/`.

## Đọc theo thứ tự

| # | File | Nội dung |
|---|---|---|
| 1 | [`TRIEN_KHAI.md`](TRIEN_KHAI.md) | **Đọc trước.** Tổng hợp 24 ý tưởng kèm nguồn, đặc tả triển khai cho đồ án, lộ trình, bảng tra nguồn |
| 2 | [`CAU_HOI.md`](CAU_HOI.md) | Nguyên văn bộ câu hỏi: onboarding (4 con vật, cờ Cá heo), câu hỏi hằng ngày, công cụ cho pilot |
| 3 | [`NGHIEN_CUU.md`](NGHIEN_CUU.md) | Mô hình chi tiết (2PM, MCTQ, HMM, Bayes) và 4 thí nghiệm trên dữ liệu giả lập |
| 4 | [`papers/`](papers/) | Các bài báo được phép đưa lên repo, kèm trích dẫn các bài còn lại |

## Code

| Thư mục | Nội dung | Chạy |
|---|---|---|
| `server/app/service/sleep/` | Chấm điểm câu hỏi, 2PM, tuần điển hình (Python thuần, dùng cho API) | `cd server && python -m pytest tests` |
| `ml/sleep-research/` | Code nghiên cứu (numpy, matplotlib) để tái tạo thí nghiệm và hình trong `NGHIEN_CUU.md` | Xem `ml/sleep-research/README.md` |
