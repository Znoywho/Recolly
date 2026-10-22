# Triển khai Module 2: Chronotype + mô hình hai quá trình

*Tài liệu chính của Module 2, **đọc file này trước**. Mỗi ý đều ghi nguồn trong ngoặc vuông, ví dụ [SD25]. Bảng tra nguồn ở mục 6 cho biết tài liệu nằm ở đâu và đọc phần nào.*

Các tài liệu và code liên quan trong repo (đường dẫn tính từ gốc repo):

| File | Dùng để |
|---|---|
| `docs/research/CAU_HOI.md` | Ngân hàng câu hỏi đầy đủ: nguyên văn từng câu, cả các câu cho những bước sau đồ án |
| `docs/research/NGHIEN_CUU.md` | Mô hình chi tiết và 4 thí nghiệm trên dữ liệu giả lập |
| `docs/research/papers/` | Các bài báo được phép đưa lên repo, kèm danh sách trích dẫn các bài còn lại |
| `docs/Script2.md` | Đề cương đồ án: các module, công nghệ, giai đoạn |
| `docs/api-v1.md` | Hợp đồng API. Module 2 dùng C1 `/chronotype/assess` và H8 `/biorhythm` |
| `server/app/service/sleep/` | **Code chạy thật** của Module 2: chấm điểm câu hỏi, 2PM, tuần điển hình |
| `server/tests/test_sleep_model.py` | Test theo tiêu chí ở mục 3.5 |
| `ml/sleep-research/` | Code nghiên cứu (numpy) để tái tạo các thí nghiệm và hình trong `NGHIEN_CUU.md` |

---

## 1. Bức tranh chung

Theo đề cương [ĐC], Module 2 (nợ ngủ, nhịp sinh học) cung cấp **"thời gian vàng"** để Module 1 xếp giờ ôn thi bằng CP-SAT, sau đó đẩy lên Google Calendar.

Trong đồ án, Module 2 lấy toàn bộ đầu vào từ **bảng hỏi**, không cần cảm biến:

```
Câu hỏi ─► MSFsc ─┬─► con vật (Sư tử / Gấu / Sói) + cờ Cá heo ─────────► thẻ kết quả
                  └─► pha φ ─┐
Giờ ngủ ngày học / nghỉ ─────┴─► 2PM, tuần điển hình ─► KSS theo giờ ─┬─► thẻ kết quả (đường năng lượng)
                                                                      └─► Module 1: CP-SAT ─► Google Calendar
```

## 2. Tổng hợp ý tưởng và nguồn

Cột "Nguồn" cho biết đọc lại ở đâu. Nguồn **[NHÓM]** nghĩa là nhóm tự suy ra hoặc tự giả định trong project, chưa có tài liệu bên ngoài xác nhận. Khi viết báo cáo cần nói rõ những chỗ này là giả định.

### 2.1 Chronotype và 4 con vật

| # | Ý tưởng | Dùng trong đồ án | Nguồn |
|---|---|---|---|
| 1 | Chronotype là một **dải liên tục**. Chia thành 4 con vật chỉ là cách gọi phổ biến, chưa được kiểm chứng khoa học | Con vật chỉ là lớp hiển thị. Bên trong luôn lưu MSFsc dạng số | [SF], [BR16] |
| 2 | **Cá heo** là người ngủ chập chờn, gần với mất ngủ, không nằm trên trục sáng–tối | Cá heo là cờ riêng, đi kèm một trong ba con còn lại | [SF] |
| 3 | Mốc "≥ 3 đêm/tuần, kéo dài ≥ 3 tháng" để gắn cờ | Câu F1–F3 | Tiêu chí tần suất của mất ngủ trong [DSM5]. Đây chỉ là sàng lọc, không chẩn đoán |
| 4 | Đo chronotype bằng **giờ giữa giấc ngủ ngày nghỉ (MSF)**, rồi trừ phần ngủ bù cuối tuần để ra **MSFsc** | Câu B2, C1–C2, D1–D3, hàm `score_mctq` | [MCTQ], [µMCTQ]; code `server/app/service/sleep/chronotype.py` |
| 5 | **Social jetlag** = \|MSF − MSW\|: độ lệch giữa đồng hồ cơ thể và lịch xã hội | Một dòng trên thẻ kết quả | [WI06] |
| 6 | **rMEQ** 5 câu làm phương án dự phòng khi không tính được MSFsc. rMEQ và MCTQ có tương quan mạnh | Câu E1–E5, chỉ hỏi khi cần | [rMEQ], [ZA05] |
| 7 | Sinh viên (khoảng 20 tuổi) có chronotype muộn nhất trong cả đời người | Ngưỡng con vật đặt quanh trung bình của sinh viên, không theo người lớn | [RO04], [SF] (phần tuổi tác) |
| 8 | Ngưỡng MSFsc 4:00 / 6:00, trung bình giả định φ = 17.4h (MSFsc ≈ 5:00) | Chia ra Sư tử / Gấu / Sói | **[NHÓM]**: `ml/sleep-research/models/synthetic.py`, cần chỉnh khi có dữ liệu thật |
| 9 | Dù là con gì cũng cần **≥ 7 tiếng** ngủ | Dòng nhắc cố định trên thẻ | [SF], [WA15] |

### 2.2 Mô hình hai quá trình (2PM)

| # | Ý tưởng | Dùng trong đồ án | Nguồn |
|---|---|---|---|
| 10 | **Process S** (áp lực ngủ) tăng khi thức, giảm khi ngủ. **Process C** là nhịp ngày đêm dạng cosin. Hai ngưỡng trên và dưới. Tham số chuẩn χs = 4.2h, χw = 18.2h, H₀⁺ = 0.67, H₀⁻ = 0.17, a = 0.12 | Toàn bộ phần mô phỏng | [SD25] Hình 1 và chú thích, phương trình (2)–(3), mục Methods; code `server/app/service/sleep/two_process.py` |
| 11 | Chronotype tương ứng với **pha φ** của nhịp ngày đêm | Đổi MSFsc sang φ | [SD25] (đoạn về quan hệ pha giữa giấc ngủ và nhịp ngày đêm, `papers/skeldon-dijk-2025.md` khoảng dòng 145); [VD07] cũng ước lượng pha như một tham số riêng của từng người |
| 12 | Dịch φ bao nhiêu thì giấc ngủ dịch bấy nhiêu, nên φ ≈ MSFsc + 12.4h. Cộng thêm **0.9h** vì MCTQ cho pha sớm hơn thật khoảng 55 phút. Con vật vẫn chia theo MSFsc, không bị ảnh hưởng bởi hệ số này | Hàm `phi_from_mid_sleep`, hằng số `MCTQ_PHI_BIAS_HOURS` | **[NHÓM]**: thí nghiệm 0 và thí nghiệm 1 trong [NC]. Hệ số 0.9h đo trên dữ liệu giả lập, cần hiệu chỉnh lại trên dữ liệu thật |
| 13 | Khi đã biết lịch ngủ thật thì **ép lịch đó vào mô hình**, không để ngưỡng tự quyết định giờ ngủ | Hàm `simulate_forced` với lịch ngủ lấy từ câu trả lời | [VD07] (dự báo theo lịch ngủ/thức đã biết); code `server/app/service/sleep/two_process.py` |
| 14 | Độ tỉnh táo A = H⁺ − H (khoảng cách tới ngưỡng ngủ); quy ra KSS = 7.5 − 9A | Đường năng lượng | **[NHÓM]**: [NC] mục 2.1 và hạn chế 3. Thang KSS lấy từ [KSS] |
| 15 | **Tuần điển hình**: đêm trước ngày đi học ngủ theo giờ ngày học, các đêm còn lại theo giờ ngày nghỉ | Dựng lịch ngủ 7 ngày | Cách chia ngày học / ngày nghỉ theo [MCTQ]; cách ghép thành tuần là **[NHÓM]** |
| 16 | 2PM **không mô tả quán tính giấc ngủ** (lờ đờ ngay sau khi dậy), nên mô hình luôn cho rằng vừa dậy là tỉnh nhất | Bỏ 30 phút đầu sau khi dậy. Không lấy "giờ vàng" làm điểm nhấn | [VD07] phần Discussion; mô hình ba quá trình [ÅF97] |
| 17 | 2PM chỉ đáng tin cho tình huống ngắn hạn. **Thiếu ngủ kéo dài** nằm ngoài phạm vi của nó | Ghi rõ: nợ ngủ trong tuần mà mô hình tính ra có thể **thấp hơn thực tế** | [VD07] phần Discussion |
| 18 | φ là đặc điểm cơ thể (trait), còn lịch ngủ là hành vi, đổi được | Phần thử "nếu…" chỉ đổi lịch, giữ nguyên φ | [VD07] (phân biệt trait và state); [SD25] dùng mô hình để thử kịch bản, ví dụ dời giờ vào học |

### 2.3 Đặt vào ứng dụng

| # | Ý tưởng | Dùng trong đồ án | Nguồn |
|---|---|---|---|
| 19 | Module 2 cấp "thời gian vàng" cho CP-SAT xếp giờ ôn thi, rồi đẩy lên Calendar | Hợp đồng dữ liệu ở mục 3.3 | [ĐC] Giai đoạn 1 |
| 20 | Backend là FastAPI (Python) | Code Module 2 nằm luôn trong `server/app/service/sleep/`, viết bằng Python thuần (không cần numpy) | [ĐC] mục Công nghệ |
| 21 | Thời khóa biểu lấy từ ảnh chụp (Module 4) | Có thời khóa biểu rồi thì B2 tự điền, chỉ hỏi để xác nhận | [ĐC] Module 4 |
| 22 | Giờ ngủ, chất lượng ngủ là **dữ liệu sức khỏe**, thuộc nhóm nhạy cảm | Màn hình đồng ý riêng trước khi hỏi | [NĐ13]; [RE] phần bảo mật |
| 23 | Lý do làm module này: 53,4% sinh viên có PSQI vượt ngưỡng, 41,3% hay ngủ gật trong giờ học buổi sáng | Phần mở đầu báo cáo | [RE] phần Mở đầu |
| 24 | Khối lượng tính toán rất nhỏ: dưới 1 giây mỗi người, kể cả khi có Bayes với 90 ngày dữ liệu | Không cần tối ưu gì cho đồ án. Bản server chạy một tuần điển hình hết khoảng 11 ms | **[NHÓM]**: đo ngày 22–23/10/2026 |

## 3. Đặc tả triển khai cho đồ án

### 3.1 Câu hỏi

Nguyên văn từng câu nằm ở `CAU_HOI.md`, mục 2.3–2.6 (cùng thư mục).

| Nhóm | Câu | Khi nào hỏi |
|---|---|---|
| Đồng ý dữ liệu | Màn A | Luôn hỏi |
| Lịch sinh hoạt | B1 (lịch có cố định không), B2 (số ngày đi học mỗi tuần) | Luôn hỏi. B2 tự điền nếu đã có thời khóa biểu |
| Giờ ngủ | C1–C2 (ngày học), D1–D3 (ngày nghỉ, có báo thức không) | Bỏ C nếu đi học 0 ngày/tuần, bỏ D nếu đi học 7 ngày/tuần |
| Dự phòng | E1–E5 (rMEQ) | Chỉ khi lịch không cố định, đi học 7 ngày, hoặc ngày nghỉ vẫn đặt báo thức |
| Cá heo | F1–F2, F3 | F3 chỉ hỏi khi F1 hoặc F2 = "3 đêm trở lên" |

Tổng cộng 9–10 câu, khoảng 2 phút. Câu F4 và các câu hằng ngày để dành cho sau đồ án.

### 3.2 Tính toán (đã viết xong trong `server/app/service/sleep/`)

| Bước | Hàm | Làm gì | File |
|---|---|---|---|
| 1 | `assess(mctq, rmeq_score, regular_schedule, sleep_quality)` | Trả về con vật, vị trí trên dải, cờ Cá heo (`sleep_concern`), MSFsc, SJL, φ và độ chắc chắn σ, khung ngủ tự nhiên, số giờ ngủ còn thiếu so với 7 tiếng. Ghi rõ kết quả tính từ MCTQ hay rMEQ | `chronotype.py` |
| 2 | `schedule_from_mctq(answers)` → `simulate_typical_week(schedule, phi)` | Dựng lịch ngủ 3 tuần theo ý #15, chạy 2PM, lấy tuần cuối. Trả về từng điểm 5 phút (S, C, A, KSS) và các giấc ngủ | `typical_week.py` |
| 3 | `TypicalWeek.days` (mỗi ngày một `DaySummary`) | Giờ dậy và giờ ngủ, KSS lúc 8h / 14h / 22h, lúc mệt nhất, số phút cố thức quá ngưỡng (A ≤ 0), khối 90 phút tỉnh nhất (đã bỏ 30 phút sau khi dậy và 1 giờ trước khi ngủ) | `typical_week.py` |
| 4 | `WeekSchedule.shift_school_onset(hours)` | Thử "nếu…": dời giờ ngủ trước ngày đi học, giữ nguyên φ, rồi chạy lại bước 2 | `typical_week.py` |

Phần 2PM nằm ở `two_process.py`. Chạy test bằng lệnh `cd server && python -m pytest tests` (cần cài `pytest`).

Hình cho báo cáo (chưa làm): `ml/sleep-research/experiments/exp4_animals.py` vẽ 3 thứ:

- đường KSS của 3 con trong cùng một ngày đi học;
- so thứ Hai với thứ Năm;
- phần thử "nếu…" (Sói ngủ sớm hơn 30 phút).

### 3.3 Hợp đồng dữ liệu Module 2 → Module 1 (CP-SAT)

Hợp đồng chính thức nằm trong `docs/api-v1.md` (C1 `/chronotype/assess`, H8 `/biorhythm`, S1 `/schedule/generate`). Phần dưới tóm tắt dữ liệu Module 2 cần đưa cho CP-SAT:

```jsonc
{
  "animal": "bear",            // lion | bear | wolf
  "dolphin": false,
  "msfsc": 4.47, "phi": 16.9, "source": "mctq",
  "step_min": 5,
  "week": [ {"day": 0, "hour": 6.5, "kss": 3.8, "asleep": false}, ... ],   // 7 ngày × 288 điểm
  "blocked": [ {"day": 0, "start": 0.0, "end": 6.5, "reason": "sleep"},
               {"day": 0, "start": 6.5, "end": 7.0, "reason": "wake_buffer"}, ... ]
}
```

- **Mục tiêu cho CP-SAT**: đặt các khối ôn thi vào chỗ có KSS thấp nhất, tức là tỉnh nhất.
- **Ràng buộc**: không đặt vào `blocked` (đang ngủ, 30 phút sau khi dậy, 1 giờ trước khi ngủ) và không trùng thời khóa biểu.
- **Endpoint**: C1 `POST /chronotype/assess` trả về con vật và tuần điển hình cho thẻ kết quả. H8 `GET /biorhythm` trả về đường KSS cho CP-SAT, dùng tuần điển hình khi người dùng chưa có nhật ký ngủ.

### 3.4 Thẻ kết quả

| Thành phần | Ví dụ | Tính từ | Nguồn |
|---|---|---|---|
| Con vật + thanh dải Sư tử ↔ Sói | 🐻 Gấu, hơi nghiêng về Sói | MSFsc, `spectrum_from_msf_sc` | ý #1, #8 |
| Huy hiệu Cá heo | "Bạn hay ngủ chập chờn", kèm gợi ý tìm hỗ trợ | F1–F3 | ý #2, #3 |
| Khung ngủ tự nhiên | "Không có báo thức, cơ thể bạn muốn ngủ khoảng 1:30–8:30" | MSFsc ± thời lượng ngủ / 2 | ý #4 |
| Social jetlag | "1 giờ 40 phút, gần bằng bay qua 2 múi giờ mỗi cuối tuần" | SJL | ý #5 |
| **Đường năng lượng** một ngày đi học | Biểu đồ KSS theo giờ, tô màu đoạn "đang cố thức quá ngưỡng" | `simulate_typical_week` | ý #10–#16 |
| **Nợ ngủ trong tuần** | "Đến thứ Năm, bạn cố thức quá ngưỡng 60 phút mỗi tối (thứ Hai là 40)" | `DaySummary.minutes_past_threshold` | ý #17 |
| **Thử "nếu…"** | Thanh kéo giờ ngủ ngày học, đường năng lượng vẽ lại theo | `WeekSchedule.shift_school_onset` | ý #18 |
| Khung tỉnh táo | Thông tin phụ, kèm chú thích về hạn chế | `DaySummary.peak_start_hour` | ý #16 |
| Lời khuyên theo con vật | Sói: ra ánh sáng buổi sáng, bớt màn hình buổi tối. Sư tử: tránh thức khuya, học khó vào buổi sáng | Bảng soạn sẵn | [SF] (phần làm việc theo chronotype) |
| Dòng nhắc | "Dù là con gì, bạn vẫn cần ít nhất 7 tiếng ngủ" | Cố định | ý #9 |

### 3.5 Kết quả chạy và tiêu chí kiểm tra

Kết quả của code server với 3 bộ câu trả lời mẫu (đi học 5 ngày/tuần, φ đã cộng 0.9h hiệu chỉnh MCTQ):

| | 🦁 Sư tử | 🐻 Gấu | 🐺 Sói |
|---|---|---|---|
| Ngủ ngày học / ngày nghỉ (đầu vào) | 22:30–6:00 / 23:00–7:00 | 0:00–6:30 / 1:00–9:00 | 1:30–6:30 / 3:30–11:30 |
| MSFsc → con vật | 2:49 → Sư tử | 4:28 → Gấu | 6:26 → Sói |
| φ | 16.1h | 17.8h | 19.8h |
| KSS 8h thứ Hai | **3.8** | 4.1 | 4.7 |
| KSS 22h thứ Hai | 7.1 | 6.6 | **6.4** |
| KSS 14h, thứ Hai → thứ Năm | 4.4 → 4.4 | 4.7 → 4.8 | 5.5 → 5.8 |
| Phút cố thức quá ngưỡng, thứ Hai → thứ Năm | 0 → 0 | 0 → 10 | 40 → 60 |

- Với Sói ngủ sớm hơn 30 phút vào ngày học (giữ nguyên φ), số phút cố thức quá ngưỡng giảm từ 40 xuống 0 (thứ Hai) và từ 60 xuống 15 (thứ Năm).
- Khi bỏ hệ số 0.9h, code server cho ra **đúng từng số** của bản chạy thử bằng code nghiên cứu ngày 23/10/2026 (ví dụ Sói: KSS 8h là 4.7, số phút cố thức thứ Hai 75 → thứ Năm 95). Test `test_typical_week_matches_research_prototype_without_bias` kiểm tra điều này.

**Tiêu chí kiểm tra** (đều có test trong `server/tests/test_sleep_model.py`, 20 test đang qua):

- 3 bộ câu trả lời ra đúng 3 con.
- Buổi sáng Sư tử tỉnh hơn Sói, buổi tối thì ngược lại.
- Nợ ngủ từ thứ Hai đến thứ Năm tăng.
- Ngủ sớm hơn thì số phút cố thức giảm.
- Giờ qua nửa đêm (ví dụ ngủ lúc 1:30) được xử lý đúng.
- Đi học 0 ngày và 7 ngày/tuần không gây lỗi.

### 3.6 Hạn chế cần ghi trong báo cáo

1. 4 con vật không phải phân loại khoa học. Kết quả chỉ để tham khảo, không phải chẩn đoán [SF], [NĐ13].
2. Ngưỡng con vật, công thức KSS = 7.5 − 9A và χw = 18.2 dùng chung cho mọi người đều là giả định **[NHÓM]**.
3. 2PM không có quán tính giấc ngủ và không mô tả tốt thiếu ngủ kéo dài [VD07]. Vì vậy giờ vàng buổi sáng có thể quá lạc quan, còn nợ ngủ trong tuần có thể bị tính thấp.
4. Kết quả dựa trên giờ ngủ do người dùng tự khai, có thể nhớ sai. Thí nghiệm 1 và 3 trong [NC] cho thấy φ tính từ MCTQ bị lệch có hệ thống.

## 4. Lộ trình

### Bước 1: Đồ án, khớp với Giai đoạn 1 của đề cương [ĐC]

| # | Việc | Ra cái gì | Ai làm (theo `.claude/CLAUDE.md`) | Trạng thái |
|---|---|---|---|---|
| 1.1 | Chốt câu hỏi ở mục 3.1 và bản dịch | `CAU_HOI.md` được nhóm duyệt | Cả nhóm | Chưa |
| 1.2 | Code tính toán Module 2 | `server/app/service/sleep/`, đạt tiêu chí ở mục 3.5 | Thành viên 1 (R18–R20) | **Xong** |
| 1.3 | Viết `ml/sleep-research/experiments/exp4_animals.py` | Hình cho báo cáo | Thành viên 1 | Chưa |
| 1.4 | Endpoint C1 `POST /chronotype/assess` và H8 `/biorhythm` (dùng tuần điển hình khi chưa có nhật ký ngủ) | JSON theo `docs/api-v1.md` | Thành viên 1 (R18, R20) | Chưa |
| 1.5 | Màn câu hỏi và thẻ kết quả (Flutter) | Giao diện demo | Thành viên 3 (R55, R59) | Chưa |
| 1.6 | Nối với CP-SAT | Giờ ôn thi rơi vào khung tỉnh táo | Thành viên 1 (R24–R27) | Chưa |
| 1.7 | Thử với 5–10 bạn trong lớp | Câu nào khó hiểu, con vật có "đúng cảm giác" không | Cả nhóm | Chưa |

### Bước 2: Nếu kịp, khớp với Giai đoạn 2 của đề cương [ĐC] (thông báo nhắc ngủ)

- **Nhắc đi ngủ**: giờ dậy ngày mai − 7.5 tiếng − 30 phút chuẩn bị [WA15].
- **Thẻ buổi sáng**: câu N1–N3 trong `CAU_HOI.md` mục 3.1. Người dùng xác nhận giờ ngủ đêm qua, và tuần điển hình được thay bằng lịch ngủ thật.

### Sau đồ án: thêm dần, mỗi mục độc lập

| Mục | Thêm gì | Cần có trước | Cắm vào đâu | Đọc |
|---|---|---|---|---|
| A | KSS hằng ngày + **Bayes** cá nhân hóa φ, χw. Con vật được phép đổi theo dữ liệu | Bước 2 (lịch ngủ thật) | Chuyển `ml/sleep-research/models/bayes_individual.py` sang server. Prior lấy từ φ, σ của `assess()` | [VD07] toàn bài; [NC] thí nghiệm 2 |
| B | Suy giờ ngủ từ **dữ liệu màn hình** (Android) bằng HMM | Quyền Usage Access | Chuyển `ml/sleep-research/models/screen_sleep.py` sang server. Tự điền câu N1 | [DI12]; [NC] thí nghiệm 1 |
| C | **Quán tính giấc ngủ**, ngủ trưa | Không | Thêm một thành phần vào `alertness` trong `two_process.py`, bỏ luật "30 phút sau khi dậy" | [ÅF97]; [VD07] phần Discussion |
| D | **Ánh sáng** (mô hình HCL), thử kịch bản như dời giờ vào học | Dữ liệu ánh sáng hoặc giờ ra ngoài trời | Thay Process C bằng mô hình có ánh sáng | [SD25] Hình 9 và tài liệu số [27] trong bài |
| E | **Pilot** khoảng 30 sinh viên, đo bằng PSQI và PVT | A hoặc B | `docs/research/CAU_HOI.md` mục 5 | [NC] mục 5 |

Lưu ý thiết kế cho mọi mục trên: **lưu câu trả lời gốc và MSFsc dạng số** ngay từ Bước 1. Như vậy khi thêm mục A thì Bayes có prior luôn, người dùng không phải làm lại bảng hỏi.

## 5. Chỗ còn mở, cần nhóm quyết

1. Ngưỡng 4:00 / 6:00 có giữ không? Sau bước thử 1.7 có thể chỉnh theo tỉ lệ thực tế trong lớp.
2. Tìm bản tiếng Việt đã kiểm định của rMEQ và KSS, hay dùng bản dịch của nhóm?
3. Thành viên 2 và 3 duyệt thay đổi hợp đồng API cho chronotype (đổi sang `lion` / `bear` / `wolf` và thêm `sleep_concern`) trước khi viết DTO.

## 6. Bảng tra nguồn

### Tài liệu có sẵn trong project

| Mã | Tài liệu | File | Đọc phần nào |
|---|---|---|---|
| [ĐC] | Đề cương đồ án Recolly | `docs/Script2.md` | Các module, công nghệ, giai đoạn 1–3 |
| [RE] | Báo cáo nghiên cứu ứng dụng Recolly | `docs/research/papers/recolly-research-report.pdf` | Mở đầu (số liệu sinh viên), "Mô hình hóa nhịp sinh học", kiến trúc offline-first, bảo mật |
| [SD25] | Skeldon & Dijk (2025). *The complexity and commonness of the two-process model of sleep regulation from a mathematical perspective.* bioRxiv, doi:10.1101/2025.01.22.634299. Giấy phép CC-BY 4.0 | `docs/research/papers/skeldon-dijk-2025.pdf`; bản text `skeldon-dijk-2025.md` cùng thư mục | Hình 1 và chú thích, có tham số chuẩn (bản text khoảng dòng 186–199). Phương trình (2)–(3) về thời lượng ngủ/thức (khoảng dòng 512–536). Methods (từ dòng 1226). Đoạn về chronotype, ánh sáng, mô hình HCL, Hình 9 (khoảng dòng 1000–1035) |
| [VD07] | Van Dongen et al. (2007). *Optimization of biomathematical model predictions for cognitive performance impairment in individuals.* SLEEP 30(9):1129–1143, doi:10.1093/sleep/30.9.1129 | **Không đưa lên repo** (có bản quyền). Tải theo DOI | Tóm tắt: 3 tham số trait và 2 trạng thái ban đầu, trong đó có pha nhịp ngày đêm. INTRODUCTION (trang 1–2 của PDF): Bayesian forecasting và prior quần thể, phương trình 2PM của bài. DISCUSSION (trang 13 của PDF, trang 1141 của tạp chí): giới hạn của 2PM với thiếu ngủ kéo dài và quán tính giấc ngủ |
| [DI12] | Dietterich, T. et al. (2012). *Machine Learning Methods for Timing of Biological Events* (slides, © Thomas G. Dietterich) | **Không đưa lên repo** (có bản quyền) | Slide 14 "Step 1: Individual Model — Each bird is a sample from a Markov Chain" |
| [NC] | Nghiên cứu nền của nhóm | `docs/research/NGHIEN_CUU.md` | Mục 2 (mô hình), mục 3 (thí nghiệm 0–3), mục 4 (hạn chế) |

### Tài liệu bên ngoài

| Mã | Tài liệu | Dùng cho |
|---|---|---|
| [SF] | Sleep Foundation. *Chronotypes.* https://www.sleepfoundation.org/how-sleep-works/chronotypes | 4 con vật, chronotype là một dải, tuổi tác, social jetlag, cách sống theo chronotype |
| [BR16] | Breus, M. J. (2016). *The Power of When.* Little, Brown | Nguồn gốc 4 con vật (không dùng quiz của sách) |
| [MCTQ] | Roenneberg, T., Wirz-Justice, A. & Merrow, M. (2003). Life between clocks. *J Biol Rhythms* 18(1):80–90 | MSF, MSFsc |
| [µMCTQ] | Ghotbi, N. et al. (2020). The µMCTQ. *J Biol Rhythms* 35(1):98–110 | Bản rút gọn của bộ câu hỏi |
| [WI06] | Wittmann, M. et al. (2006). Social jetlag: misalignment of biological and social time. *Chronobiol Int* 23(1–2):497–509 | Social jetlag |
| [RO04] | Roenneberg, T. et al. (2004). A marker for the end of adolescence. *Curr Biol* 14(24):R1038–R1039 | Chronotype muộn nhất vào khoảng 20 tuổi |
| [rMEQ] | Adan, A. & Almirall, H. (1991). *Pers Individ Dif* 12(3):241–253 | 5 câu dự phòng |
| [ZA05] | Zavada, A. et al. (2005). *Chronobiol Int* 22(2):267–278 | Tương quan MCTQ–MEQ (r = −0.73) |
| [KSS] | Åkerstedt, T. & Gillberg, M. (1990). *Int J Neurosci* 52(1–2):29–37 | Thang buồn ngủ 1–9 |
| [ÅF97] | Åkerstedt, T. & Folkard, S. (1997). The three-process model of alertness. *Chronobiol Int* 14(2):115–123 | Quán tính giấc ngủ (Process W). Cũng là tài liệu số 34 trong [VD07] |
| [WA15] | Watson, N. F. et al. (2015). Recommended amount of sleep for a healthy adult. *Sleep* 38(6):843–844 | Mức ≥ 7 tiếng |
| [DSM5] | American Psychiatric Association (2013). *DSM-5* | Mốc tần suất và thời gian của mất ngủ |
| [NĐ13] | Nghị định 13/2023/NĐ-CP về bảo vệ dữ liệu cá nhân | Dữ liệu sức khỏe là dữ liệu nhạy cảm |
