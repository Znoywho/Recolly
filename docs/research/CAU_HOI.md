# Bộ câu hỏi Module nhịp sinh học (v0.1)

*Ngân hàng câu hỏi đầy đủ cho Module 2 của Recolly. Phạm vi đồ án, nguồn của từng ý và lộ trình xem `TRIEN_KHAI.md` (đọc file đó trước). Nền tảng mô hình xem `NGHIEN_CUU.md`. Code chấm điểm: `server/app/service/sleep/chronotype.py`.*

---

## 0. Nguyên tắc

- **Mỗi câu hỏi phải đổ vào một tham số hoặc một quyết định cụ thể.** Câu nào không dùng tới thì bỏ.
- **Dùng công cụ đã được kiểm chứng** (µMCTQ, rMEQ, KSS). Chỉ tự viết câu mới khi không có công cụ miễn phí phù hợp (cờ Cá heo).
- **Ngắn**: onboarding ≤ 3 phút, hằng ngày ≤ 30 giây.
- **Hỏi giờ "ngủ thiếp đi"**, không hỏi giờ "lên giường". Sinh viên hay nằm lướt điện thoại rất lâu trước khi ngủ.
- **Con vật chỉ là lớp hiển thị.** Bên trong luôn lưu MSFsc và φ dạng số liên tục.
- **Không chẩn đoán.** Cờ Cá heo chỉ dùng để điều chỉnh mô hình và gợi ý người dùng tìm hỗ trợ.

## 1. Tổng quan

| Tầng | Khi nào | Thời lượng | Mục đích |
|---|---|---|---|
| Onboarding | Một lần, lúc cài app | 2–3 phút | Con vật, prior φ, cờ Cá heo, social jetlag, nợ ngủ ban đầu |
| Hằng ngày | Sáng + 2–4 lần trong ngày | ≤ 30 giây | Lịch ngủ thật và KSS để Bayes cập nhật φ, χ_w |
| Hằng tuần / tháng | Gộp vào thẻ buổi sáng | ≤ 1 phút | Theo dõi thay đổi, đánh giá lịch xếp |
| Chỉ dùng trong pilot | Đầu và cuối pilot | 10–15 phút | Công cụ nghiên cứu để kiểm chứng |

## 2. Onboarding

### 2.1 Luồng màn hình

```
[A  Đồng ý dữ liệu sức khỏe]
        │
[B1 Lịch học/làm có cố định?] ──Không (làm ca, lịch đảo)──────────────┐
        │ Có                                                          │
[B2 Số ngày phải dậy theo lịch / tuần = WD]                           │
        │  WD = 0 → bỏ C           WD = 7 → bỏ D, sang E ─────────────┤
[C1–C2  Ngày đi học: ngủ lúc / dậy lúc]                               │
[D1     Ngày nghỉ có đặt báo thức?] ──Có → vẫn hỏi D2–D3, gắn cờ ─────┤
[D2–D3  Ngày nghỉ: ngủ lúc / dậy lúc]                                 │
        │                                                             ▼
        ├──── tùy chọn: "Trả lời thêm 5 câu để kết quả chắc hơn" ──► [E  rMEQ 5 câu]
        │                                                             │
[F1–F2  Mất ngủ đầu giấc / thức giấc giữa đêm] ◄──────────────────────┘
        │  F1 hoặc F2 = "3 đêm trở lên" → [F3 Kéo dài bao lâu?]
[F4     Tự đánh giá chất lượng giấc ngủ]
        │
[G  Thẻ kết quả]
        │
[H  Kết nối: Google Calendar, thông báo, (Android) dữ liệu màn hình]
```

Nhánh chính có 10–11 câu trả lời. Nếu phải làm thêm rMEQ thì 15–16 câu.

### 2.2 Phần A: Đồng ý

Đây là màn hình, không phải câu hỏi. Giờ ngủ và chất lượng giấc ngủ là **thông tin sức khỏe**, thuộc nhóm dữ liệu cá nhân nhạy cảm theo Nghị định 13/2023/NĐ-CP. Vì vậy cần:

- đồng ý riêng, rõ ràng, không đánh dấu sẵn;
- nói rõ dữ liệu lưu trên máy (offline-first), khi nào thì đồng bộ;
- một câu: "Recolly không phải thiết bị y tế và không chẩn đoán bệnh".

### 2.3 Phần B: Lịch sinh hoạt (dựa trên µMCTQ)

| ID | Câu hỏi | Trả lời | Đổ vào |
|---|---|---|---|
| B1 | Lịch học hoặc làm của bạn có lặp lại đều mỗi tuần không? | Có / Không, tôi làm ca hoặc lịch thay đổi liên tục | Chọn nhánh MCTQ hay rMEQ |
| B2 | Mỗi tuần bạn có mấy ngày phải dậy theo lịch (đi học, đi làm)? | 0–7 | `work_days` (WD) |

Khi đã có thời khóa biểu (chụp ảnh ở Module 4 hoặc lấy từ Google Calendar), B2 được điền sẵn, chỉ hỏi để xác nhận.

### 2.4 Phần C và D: Giờ ngủ (dựa trên µMCTQ)

Dòng hướng dẫn chung trên màn hình: *"Trả lời theo một tuần học bình thường gần đây, không tính mùa thi hay kỳ nghỉ. 'Ngủ thiếp đi' là lúc bạn thực sự ngủ, không phải lúc lên giường hay lúc bắt đầu lướt điện thoại."*

| ID | Câu hỏi | Trả lời | Hiện khi | Đổ vào |
|---|---|---|---|---|
| C1 | Ngày đi học, bạn thường ngủ thiếp đi lúc mấy giờ? | Chọn giờ, bước 15' | WD ≥ 1 | `sleep_onset_work` |
| C2 | Ngày đi học, bạn thường thức dậy lúc mấy giờ? | Chọn giờ, bước 15' | WD ≥ 1 | `sleep_end_work` |
| D1 | Ngày nghỉ, bạn có đặt báo thức không? | Không / Có | WD ≤ 6 | Cờ "MSF bị báo thức" |
| D2 | Ngày nghỉ không có báo thức, bạn thường ngủ thiếp đi lúc mấy giờ? | Chọn giờ, bước 15' | WD ≤ 6 | `sleep_onset_free` |
| D3 | Ngày nghỉ không có báo thức, bạn thường thức dậy lúc mấy giờ? | Chọn giờ, bước 15' | WD ≤ 6 | `sleep_end_free` |

**Kiểm tra ngay khi nhập:**

- Thời lượng ngủ < 4h hoặc > 12h: hỏi lại "Bạn chắc chứ?" (vẫn cho giữ nguyên).
- Giờ dậy nhỏ hơn giờ ngủ là bình thường (qua nửa đêm). `score_mctq` đã xử lý bằng `% 24`.
- WD = 0 (ví dụ đang nghỉ hè): truyền giờ ngày nghỉ vào cả hai chỗ. Khi đó SDweek = SDf, nên MSFsc = MSF.

### 2.5 Phần E: rMEQ (Adan & Almirall 1991)

**Bắt buộc** khi B1 = Không, WD = 7, hoặc D1 = Có, tức là những trường hợp không tính được MSFsc đáng tin. **Tùy chọn** trong các trường hợp còn lại. Nếu người dùng bỏ qua ở onboarding thì nhắc lại trong tuần đầu.

| ID | Câu hỏi | Lựa chọn (điểm) |
|---|---|---|
| E1 | Nếu hoàn toàn được tự do sắp xếp ngày của mình, bạn sẽ dậy lúc mấy giờ? | 5:00–6:30 (5) · 6:30–7:45 (4) · 7:45–9:45 (3) · 9:45–11:00 (2) · 11:00–12:00 (1) |
| E2 | Trong nửa giờ đầu sau khi thức dậy buổi sáng, bạn cảm thấy thế nào? | Rất mệt (1) · Khá mệt (2) · Khá sảng khoái (3) · Rất sảng khoái (4) |
| E3 | Buổi tối, khoảng mấy giờ bạn bắt đầu thấy mệt và cần đi ngủ? | 20:00–21:00 (5) · 21:00–22:15 (4) · 22:15–0:45 (3) · 0:45–2:00 (2) · 2:00–3:00 (1) |
| E4 | Bạn thường thấy mình ở trạng thái tốt nhất vào khoảng giờ nào trong ngày? | 5:00–8:00 (5) · 8:00–10:00 (4) · 10:00–17:00 (3) · 17:00–22:00 (2) · 22:00–5:00 (1) |
| E5 | Có người là "người buổi sáng", có người là "người buổi tối". Bạn thấy mình thuộc loại nào? | Chắc chắn buổi sáng (6) · Nghiêng về buổi sáng (4) · Nghiêng về buổi tối (2) · Chắc chắn buổi tối (0) |

Tổng điểm 4–25, phân loại bằng `rmeq_category`. *Đây là bản dịch làm việc. Cần tìm bản tiếng Việt đã kiểm định, nếu không có thì dịch xuôi rồi dịch ngược.*

### 2.6 Phần F: Chất lượng giấc ngủ (cờ Cá heo)

Phần này nhóm tự viết, không dùng ISI hay PSQI vì cả hai có bản quyền khi dùng thương mại. Mốc "3 đêm/tuần" và "3 tháng" lấy theo tiêu chí tần suất và thời gian thường dùng cho mất ngủ (DSM-5). **Đây chỉ là cờ sàng lọc, không phải chẩn đoán.**

| ID | Câu hỏi | Trả lời | Hiện khi |
|---|---|---|---|
| F1 | Trong một tuần bình thường, có mấy đêm bạn mất hơn 30 phút mới ngủ được? | 0 · 1–2 · 3 trở lên | Luôn hiện |
| F2 | Có mấy đêm bạn thức giấc giữa đêm hoặc dậy quá sớm, rồi khó ngủ lại? | 0 · 1–2 · 3 trở lên | Luôn hiện |
| F3 | Tình trạng này kéo dài bao lâu rồi? | < 1 tháng · 1–3 tháng · > 3 tháng | F1 hoặc F2 = 3 trở lên |
| F4 | Nhìn chung, bạn đánh giá chất lượng giấc ngủ của mình thế nào? | Rất tốt · Khá tốt · Khá tệ · Rất tệ | Luôn hiện |

**Quy tắc:**

- **Cờ Cá heo**: (F1 hoặc F2 = 3 trở lên) **và** F3 = > 3 tháng.
- **Theo dõi**: (F1 hoặc F2 = 3 trở lên) nhưng F3 < 3 tháng. Không hiện nhãn, chỉ hỏi lại sau 4 tuần.
- F4 không dùng để gắn cờ. F4 là mốc ban đầu để sau này so sánh xem app có giúp gì không.

### 2.7 Cách tính kết quả

```
nếu B1 = Không hoặc WD = 7:
    nguồn = rMEQ
    con vật = Sư tử nếu rMEQ ≥ 18, Gấu nếu 12–17, Sói nếu ≤ 11
    φ0 = 15.4 / 17.4 / 19.4 h theo con vật;  σ = 1.5 h
ngược lại:
    r = score_mctq(...)                       # MSFsc, SJL, SDweek
    φ0 = phi_from_mid_sleep(r.MSFsc) + 0.9 h  # ≈ MSFsc + 12.4 h, cộng hiệu chỉnh lệch của MCTQ
    σ = 1.0 h,  hoặc 1.5 h nếu D1 = Có
    nếu có rMEQ và hai nguồn lệch nhau 2 bậc (Sư tử với Sói):  σ += 0.5 h
    con vật theo MSFsc (bảng dưới)
vị trí trên dải  = spectrum_from_msf_sc(MSFsc) # 5 mức, dùng cho thanh trượt
nợ ngủ ước tính  = max(0, 7 − SDweek)          # giờ mỗi đêm
cờ Cá heo        = theo mục 2.6
```

| Con vật | MSFsc | φ0 | Ngủ tự nhiên theo 2PM* |
|---|---|---|---|
| 🦁 Sư tử | < 4:00 | < 16.4h | khoảng 23:00–07:00 |
| 🐻 Gấu | 4:00–6:00 | 16.4–18.4h | khoảng 01:00–09:00 |
| 🐺 Sói | ≥ 6:00 | ≥ 18.4h | khoảng 03:00–11:00 |
| 🐬 Cá heo | Cờ riêng, đi kèm một trong ba con trên | Không đổi φ | — |

\* Mô phỏng 2PM với tham số chuẩn, không báo thức, tại MSFsc = 3:00 / 5:00 / 7:00 (giá trị đại diện của từng nhóm).

**Lưu ý về ngưỡng:**

- Mốc 4:00 và 6:00 đang đặt quanh trung bình giả định của mô hình (φ = 17.4h, tức MSFsc ≈ 5:00). Vì vậy "Gấu" ở đây là sinh viên điển hình, không trùng giờ ngủ trong bài của Breus.
- Khi có dữ liệu thật, chỉnh lại ngưỡng theo bách phân vị (ví dụ 20 / 60 / 20).
- Thí nghiệm 1 và 3 cho thấy φ tính từ MCTQ bị lệch có hệ thống, nên prior chỉ là điểm xuất phát. Bayes sẽ sửa dần.

### 2.8 Phần G: Thẻ kết quả

| Thành phần | Ví dụ | Lấy từ |
|---|---|---|
| Con vật + thanh dải Sư tử ↔ Sói | 🐻 Gấu, hơi nghiêng về Sói | MSFsc, `spectrum_from_msf_sc` |
| Huy hiệu Cá heo (nếu có) | "Bạn hay ngủ chập chờn" + gợi ý tìm hỗ trợ | F1–F3 |
| Khung ngủ tự nhiên | "Không có báo thức, cơ thể bạn muốn ngủ khoảng 1:30–8:30" | MSFsc ± SDweek/2 |
| Social jetlag | "1 giờ 40 phút, gần bằng bay qua 2 múi giờ mỗi cuối tuần" | SJL |
| Ngủ trung bình | "6 giờ 20 phút/đêm, thiếu khoảng 40 phút so với mức 7 tiếng" | SDweek |
| Đường năng lượng, nợ ngủ trong tuần, thử "nếu…" | Xem `TRIEN_KHAI.md` mục 3.4 | 2PM chạy trên tuần điển hình dựng từ C1–D3, với φ0 và χ_w = 18.2 |
| Khung tỉnh táo (thông tin phụ) | Các khối 90 phút tỉnh nhất trong một ngày đi học | Như trên, `DaySummary.peak_start_hour` |
| Độ chắc chắn | "Thấp: mới dựa trên bảng hỏi. Sẽ rõ hơn sau 1–2 tuần" | σ |
| Dòng nhắc cố định | "Dù là con gì, bạn vẫn cần ít nhất 7 tiếng ngủ" | — |

Lưu ý: 2PM chưa có quán tính giấc ngủ, nên mô hình luôn cho rằng tỉnh nhất là ngay sau khi dậy. Vì vậy phải loại 30 phút đầu sau khi dậy, như thí nghiệm 3 đã làm, và không lấy khung tỉnh táo làm điểm nhấn (`TRIEN_KHAI.md` ý #16).

### 2.9 Phần H: Kết nối

Phần này đặt **sau** thẻ kết quả: người dùng thấy giá trị trước, rồi mới được xin quyền.

| Quyền | Để làm gì | Khi nào cần (theo `TRIEN_KHAI.md` mục 4) |
|---|---|---|
| Google Calendar | Đẩy lịch ôn thi, lấy lịch học thay cho B2 | Bước 1 (đồ án) |
| Thông báo | Nhắc đi ngủ, thẻ buổi sáng | Bước 2 |
| Dữ liệu màn hình (Android, Usage Access) | HMM tự điền giờ ngủ | Sau đồ án, mục B |
| Health Connect / HealthKit | Giờ ngủ từ đồng hồ thông minh, nếu có | Sau đồ án, mục B |

## 3. Câu hỏi hằng ngày

### 3.1 Thẻ buổi sáng (khoảng 15 giây)

Hiện ở lần mở app đầu tiên sau giờ dậy dự kiến + 30 phút. Nếu không mở app thì gửi thông báo lúc giờ dậy + 60 phút, trừ khi đang trong giờ học.

| ID | Câu hỏi | Trả lời | Đổ vào |
|---|---|---|---|
| N1 | Đêm qua bạn ngủ khoảng **23:40 → 7:05**, đúng không? | Đúng / Sửa (kéo hai đầu thanh) | Lịch ngủ cho Bayes. Đây là nguồn quan trọng nhất (xem NGHIEN_CUU mục 5) |
| N2 | Ngủ có ngon không? | 4 mức, như F4 | Theo dõi chất lượng ngủ |
| N3 | Hôm qua bạn có ngủ trưa không? | Không · < 30' · 30–90' · > 90', kèm giờ bắt đầu | Thêm giấc ngủ trưa vào lịch ngủ (2PM coi ngủ trưa là một giấc ngủ) |
| N4 | Hôm qua có gì đặc biệt không? (tùy chọn) | Chip: Thi · Thức khuya học · Ốm · Đi chơi khuya · Cà phê sau 15h · Rượu bia | Giảm trọng số ngày bất thường, dùng cho phân tích |

Giờ điền sẵn ở N1: ban đầu dùng giờ ngủ quen thuộc (C1–D3) hoặc giờ của hôm trước; khi đã có HMM (mục B sau đồ án) thì dùng kết quả HMM.

### 3.2 KSS (Åkerstedt & Gillberg 1990), khoảng 2 giây mỗi lần

**N5.** *"Trong 5 phút vừa rồi, bạn thấy mình thế nào?"*

| Điểm | Nhãn |
|---|---|
| 1 | Cực kỳ tỉnh táo |
| 2 | Rất tỉnh táo |
| 3 | Tỉnh táo |
| 4 | Khá tỉnh táo |
| 5 | Không tỉnh cũng không buồn ngủ |
| 6 | Hơi có dấu hiệu buồn ngủ |
| 7 | Buồn ngủ, nhưng giữ tỉnh không khó |
| 8 | Buồn ngủ, phải cố mới giữ tỉnh |
| 9 | Rất buồn ngủ, phải cố lắm, đang chống lại cơn buồn ngủ |

**Lịch hỏi:**

- 2–4 lần mỗi ngày, rơi ngẫu nhiên vào 4 khung: sáng, trưa, chiều, tối.
- Không hỏi trong giờ học (lấy từ Calendar).
- Không hỏi trong 1 giờ trước giờ ngủ dự kiến. Hỏi lúc đó vừa làm người dùng bật màn hình, vừa làm nhiễu dữ liệu cho HMM.
- Bỏ qua không bị phạt. Nếu người dùng bỏ 3 lần liên tiếp thì giảm xuống 2 lần/ngày.

KSS là likelihood của Bayes: KSS ~ N(7.5 − 9A, σ²).

## 4. Câu hỏi hằng tuần và hằng tháng

| ID | Khi nào | Câu hỏi | Mục đích |
|---|---|---|---|
| W1 | Tuần đầu, nếu chưa làm | rMEQ (E1–E5) | Đối chiếu với MCTQ, thu hẹp σ |
| W2 | Thẻ sáng thứ Hai (khi app đã xếp lịch ôn thi) | "Lịch học app xếp tuần trước có hợp với bạn không?" (1–5) và "Bạn đã học theo mấy khối?" | Đánh giá phần xếp lịch |
| M1 | Mỗi 4 tuần | Làm lại C1–D3 | Theo dõi SJL; so con vật từ bảng hỏi với con vật từ Bayes |
| M2 | Mỗi 4 tuần | Làm lại F1–F4 | Theo dõi cờ Cá heo và nhóm "theo dõi" |

## 5. Công cụ chỉ dùng trong pilot

Những công cụ này **không** đưa vào app phát hành. Chỉ dùng trong pilot khoảng 30 sinh viên (`TRIEN_KHAI.md` mục 4, phần sau đồ án, mục E).

| Công cụ | Dùng để | Lưu ý |
|---|---|---|
| MCTQ đầy đủ (Roenneberg 2003) | So với bản rút gọn ở mục 2.4 | Miễn phí cho nghiên cứu |
| PSQI (Buysse 1989) | Chất lượng giấc ngủ, đầu và cuối pilot | Cần xin phép University of Pittsburgh |
| ISI (Bastien 2001) | Kiểm tra lại cờ Cá heo | Có bản quyền, cần license |
| Consensus Sleep Diary (Carney 2012) | Nhật ký đầy đủ hơn N1–N3 | Dùng để kiểm chứng N1 |
| PVT-B 3 phút (Basner 2011) | Đo tỉnh táo khách quan, mỗi ngày một lần | Kiểm chứng KSS và dự báo 2PM |

## 6. Kiểm định bộ câu hỏi trước khi code nhiều

| Bước | Làm gì | Đạt khi |
|---|---|---|
| 1. Dịch | Tìm bản tiếng Việt đã kiểm định của rMEQ, KSS, MCTQ. Không có thì dịch xuôi, dịch ngược | Có bản dịch được nhóm thống nhất |
| 2. Phỏng vấn nhận thức | 5–8 sinh viên vừa làm vừa nói to suy nghĩ. Kiểm tra họ có phân biệt "ngủ thiếp đi" với "lên giường", có hiểu "ngày nghỉ không báo thức" | Không còn câu nào bị hiểu sai |
| 3. Thử nghiệm | 30+ sinh viên làm onboarding | ≥ 90% làm xong, thời gian trung vị ≤ 3 phút |
| 4. Làm lại sau 2 tuần | Cùng nhóm làm lại C, D, E | Con vật trùng ≥ 80%; MSFsc lệch trung vị ≤ 30' |
| 5. Hội tụ | Tương quan giữa MSFsc và điểm rMEQ | Âm và đủ mạnh (Zavada 2005 báo cáo r = −0.73 giữa MSFsc và MEQ đầy đủ) |
| 6. Phân bố | Tỉ lệ Sư tử / Gấu / Sói trên sinh viên thật | Dùng để chỉnh ngưỡng ở mục 2.7 |

## Tài liệu tham khảo

- Ghotbi, N. et al. (2020). The µMCTQ: an ultra-short version of the Munich ChronoType Questionnaire. *J Biol Rhythms* 35(1):98–110.
- Roenneberg, T., Wirz-Justice, A. & Merrow, M. (2003). Life between clocks: daily temporal patterns of human chronotypes. *J Biol Rhythms* 18(1):80–90.
- Adan, A. & Almirall, H. (1991). Horne & Östberg morningness–eveningness questionnaire: a reduced scale. *Pers Individ Dif* 12(3):241–253.
- Horne, J. A. & Östberg, O. (1976). A self-assessment questionnaire to determine morningness–eveningness in human circadian rhythms. *Int J Chronobiol* 4(2):97–110.
- Zavada, A. et al. (2005). Comparison of the Munich Chronotype Questionnaire with the Horne–Östberg's morningness–eveningness score. *Chronobiol Int* 22(2):267–278.
- Åkerstedt, T. & Gillberg, M. (1990). Subjective and objective sleepiness in the active individual. *Int J Neurosci* 52(1–2):29–37.
- Buysse, D. J. et al. (1989). The Pittsburgh Sleep Quality Index. *Psychiatry Res* 28(2):193–213.
- Bastien, C. H., Vallières, A. & Morin, C. M. (2001). Validation of the Insomnia Severity Index. *Sleep Med* 2(4):297–307.
- Carney, C. E. et al. (2012). The Consensus Sleep Diary. *Sleep* 35(2):287–302.
- Basner, M., Mollicone, D. & Dinges, D. F. (2011). Validity and sensitivity of a brief psychomotor vigilance test (PVT-B). *Acta Astronaut* 69(11–12):949–959.
- Sleep Foundation. *Chronotypes.* https://www.sleepfoundation.org/how-sleep-works/chronotypes
- Nghị định 13/2023/NĐ-CP về bảo vệ dữ liệu cá nhân.
