# TODO — Thí nghiệm: có nên fine-tune model giọng nói không?

Câu hỏi cần trả lời: **fine-tune PhoWhisper có làm tăng Task Success Rate (TSR) nhiều hơn các cách rẻ hơn không?**

Nguyên tắc thí nghiệm:
- **Một tập test cố định**, không bao giờ dùng để train, mọi phương án đều đo trên đúng tập này.
- **So sánh theo cặp**: cùng một câu, phương án A đúng/sai vs phương án B đúng/sai.
- **Luôn kèm khoảng tin cậy**: chênh lệch nhỏ hơn khoảng tin cậy = chưa kết luận được.
- **Thang baseline từ rẻ đến đắt**: fine-tune chỉ đáng làm nếu thắng cả các bậc rẻ hơn.

Hiện trạng (10/11/2026): tập eval mới có 2 câu audio, PhoWhisper-small nghe "đặt lịch mới" thành
"đặc lịch mời" → có dấu hiệu lỗi ASR thật, nhưng 2 câu thì chưa kết luận được gì.

---

## Ngày mai (12/11/2026)

### 1. Hoàn thành metric trong `voice_eval.ipynb` mục 4 (~1.5h)
- [ ] `accuracy`, `real_time_factor`, `token_f1`, `keyword_recall`
- [ ] `macro_f1`, `mean_absolute_error_hours`
- [ ] `confidence_interval_95`: `p ± 1.96 · sqrt(p(1−p)/n)`
- [ ] `word_error_rate`: `WER = (S + D + I) / N`, tính bằng quy hoạch động
      `D[i][j] = min(D[i−1][j] + 1, D[i][j−1] + 1, D[i−1][j−1] + [h_i ≠ r_j])`
- [ ] Cell test in ra toàn ✅

### 2. Viết kịch bản thu âm: 60 câu (~1h) — xong, xem `data/recording_script.md`
Mỗi câu gắn `tags` để sau này cắt lát kết quả. Phân bổ gợi ý:
- [x] 15 câu chỉ có giờ (`time_only`): "đặt lịch mới học giải tích lúc mười bảy giờ"
- [x] 15 câu ngày tương đối (`relative_date`): "thứ sáu tuần sau nộp đồ án"
- [x] 10 câu không có deadline (`no_deadline`)
- [x] 10 câu chen tiếng Anh (`code_switch`): "deadline", "OOP", "midterm", "slide"
- [x] 10 câu tên môn học / thuật ngữ khó (`domain_term`): "xác suất thống kê", "cấu trúc dữ liệu"
- [x] Ít nhất 1/3 số câu **không** bắt đầu bằng "đặt lịch mới" (tránh model chỉ thuộc mẫu câu)

### 3. Thu âm tập test (~1.5h)
- [ ] 3 người, mỗi người thu 20 câu theo cột "Người đọc" trong `data/recording_script.md` → 60 clip
      (bằng điện thoại, đúng điều kiện dùng thật: phòng trọ, hơi ồn)
- [ ] Nếu kịp: mỗi người đọc thêm phần của người kế tiếp → 120 clip, mỗi câu có 2 giọng
- [x] Thêm 60 dòng a003–a062 vào `data/voice_eval.jsonl` kèm nhãn `expected` và trường `speaker`
- [ ] Đọc lại nhãn `expected` một lượt (đặc biệt `category` của các câu mơ hồ) và sửa nếu không đồng ý
- [ ] Đặt tên file thu âm đúng như trường `audio` (ví dụ `s01_a003.m4a`); notebook mục 2 sẽ
      `assert` lỗi cho tới khi đủ file audio
- [ ] Ghi chú: cả 3 giọng đều nằm trong test → nếu sau này fine-tune, tập train phải thu từ **người khác**
      (hoặc thêm 1–2 người chỉ-có-trong-test) thì mới đo được overfit giọng

Khoảng tin cậy với p ≈ 0.5: 60 clip → ±13%, 120 clip → ±9%. Với n = 2 thì vô nghĩa.

### 4. Chạy baseline trên Kaggle (~1h, chủ yếu ngồi chờ)
- [ ] A0: `PhoWhisper-small` (đang dùng)
- [ ] A1: `PhoWhisper-medium`, `PhoWhisper-large` (không cần train, chỉ đổi model)
- [ ] A2a: A0 + LLM tự sửa lỗi nghe (chỉ đổi prompt, sửa `build_system_prompt` ở mục 6)
  - [ ] Dặn LLM: transcript là từ ASR, có thể sai từ **nghe giống nhau** ("đặc lịch mời" = "đặt lịch mới");
        suy ra câu gốc rồi mới trích xuất; không tự đổi số / giờ / ngày
  - [ ] Thêm 3–5 ví dụ few-shot lấy từ lỗi thật (câu few-shot **không** được nằm trong tập test)
  - [ ] Bơm danh sách môn học vào prompt: `Known subjects: Giải tích, Cấu trúc dữ liệu, ...`
  - [ ] Thêm trường `corrected_transcript` vào `TODO_DRAFT_SCHEMA`, đặt **trước** `title`
  - [ ] Đo thêm WER của `corrected_transcript` so với `transcript_gold` (so với WER gốc của A0)
- [ ] A2b: A2a + N-best (đưa 5 giả thuyết của Whisper cho LLM thay vì 1)
  - [ ] Trong `AsrRunner`: gọi `model.generate(num_beams=5, num_return_sequences=5)`, lưu thêm
        trường `hypotheses` (list 5 câu) vào `asr_results.jsonl`
  - [ ] Prompt: liệt kê 5 câu, dặn "chỗ các câu khác nhau là chỗ ASR không chắc"
  - [ ] Đo **oracle**: tỉ lệ câu mà `transcript_gold` nằm trong 5 giả thuyết → trần trên của N-best
- [ ] Kiểm tra sửa quá tay (cho cả A2a, A2b): trên các câu A0 **đã nghe đúng**, TSR không được giảm
- [ ] Lưu bảng: WER, keyword recall, TSR_gold, TSR_asr, Δ_ASR, RTF — theo từng model và từng `tag`
- [ ] Đo RTF của small/medium trên **máy local (CPU)**, vì server không có GPU

### 5. Đọc lỗi và phân loại (~45 phút)
Mở cell "Inspect failures", gán mỗi câu sai vào một loại:
- [ ] `asr_command` — sai cụm lệnh ("đặt lịch" → "đặc lịch")
- [ ] `asr_domain` — sai tên môn / thuật ngữ / tiếng Anh
- [ ] `asr_time` — sai giờ, ngày
- [ ] `parser_date` — transcript đúng nhưng tính ngày sai
- [ ] `parser_other` — sai category / title
- [ ] Đếm số lượng từng loại → loại nào nhiều nhất là thứ cần sửa trước

### 6. Ra quyết định (viết 3–5 dòng kết luận vào cuối file này)
| Quan sát | Quyết định |
|---|---|
| Δ_ASR < 5% | Không fine-tune ASR. Tập trung parser. |
| A1 (medium) xoá gần hết Δ_ASR và RTF trên CPU < 1 | Đổi `PHOWHISPER_MODEL`, không fine-tune. |
| A2a xoá gần hết Δ_ASR | Giữ small, đổi prompt, không fine-tune. |
| A2a chưa đủ, A2b xoá gần hết Δ_ASR (và oracle cao) | Giữ small, dùng N-best — kiểm tra RTF vì beam search chậm hơn. |
| Δ_ASR ≥ 10%, lỗi chủ yếu `asr_domain` / `asr_command`, medium quá chậm | **Fine-tune small bằng LoRA** → sang giai đoạn 2. |

---

## Giai đoạn 2 — chỉ làm nếu bước 6 nói "fine-tune"

- [ ] Thu tập train: 1–2 giờ audio, câu **khác** tập test, người nói **khác** 2 người test
- [ ] Tách 10% train làm validation (để chọn checkpoint, không dùng test)
- [ ] A3: LoRA trên `PhoWhisper-small` (Kaggle T4)
- [ ] Đo A3 trên đúng tập test ở trên, so với A0/A1/A2a/A2b
- [ ] **Paired bootstrap**: lấy mẫu lại các câu test có hoàn lại 1000 lần, mỗi lần tính
      `ΔTSR = TSR(A3) − TSR(A0)`; nếu khoảng 2.5%–97.5% của ΔTSR không chứa 0 → cải thiện là thật
- [ ] Kiểm tra "quên": đo WER trên ~100 câu tiếng Việt thông thường (ví dụ tập test VIVOS)
      trước và sau fine-tune — không được tệ đi rõ rệt
- [ ] Kiểm tra theo người nói: A3 có tốt hơn trên người nói không có trong train không (nếu chỉ tốt
      trên giọng của mình → overfit giọng)
- [ ] RTF của A3 trên CPU không đổi so với A0 (sau khi merge LoRA)

## Kết luận
_(điền sau bước 6)_
