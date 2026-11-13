# Quy tắc gán `category` cho todo

Dùng cho cả hai việc: gán nhãn `expected.category` trong `voice_eval.jsonl` **và** viết prompt cho LLM.
Hai bên phải dùng đúng một bộ quy tắc, nếu không thì điểm category đo được là đo sự lệch giữa người gán nhãn
và prompt, chứ không phải đo model.

Xét theo thứ tự, gặp quy tắc nào khớp trước thì dừng:

| # | category | khi nào | ví dụ |
|---|---|---|---|
| 1 | `exam` | **làm bài thi / kiểm tra**, hoặc **ôn cho một bài thi cụ thể** (thi, kiểm tra, quiz, midterm, cuối kỳ, vấn đáp) | "thứ năm thi vật lý", "ôn thi giải tích", "ôn midterm OOP" |
| 2 | `assignment` | **tạo ra và nộp một sản phẩm học tập** (bài tập, báo cáo, đồ án, tiểu luận, lab, slide, code) — kể cả các bước làm ra nó (họp nhóm đồ án, tìm tài liệu cho tiểu luận, fix bug project) | "nộp báo cáo", "họp nhóm đồ án", "push code lên GitHub" |
| 3 | `study` | **học / ôn / đọc để hiểu bài**, không gắn với bài thi hay sản phẩm nộp cụ thể | "học giải tích lúc năm giờ", "đi thư viện", "ôn lại chương ba" |
| 4 | `personal` | việc **đời sống cá nhân**: sức khoẻ, gia đình, nhà cửa, mua sắm, giải trí, thể thao | "chạy bộ", "gọi cho mẹ", "mua sách giáo trình", "đọc sách" |
| 5 | `other` | **hành chính / thủ tục ở trường** và mọi thứ còn lại: nộp đơn, đăng ký học phần, đóng học phí, gặp thầy, hỏi điểm, câu lạc bộ, họp không rõ mục đích | "lên văn phòng khoa nộp đơn", "đóng học phí", "meeting với nhóm" |

Ca khó, đã chốt:
- "ôn thi X" / "ôn midterm" → `exam` (quy tắc 1 đứng trước quy tắc 3).
- "họp nhóm đồ án" → `assignment` (có đồ án). "meeting với nhóm" không nói việc gì → `other`.
- "làm lại bài kiểm tra bị sai" → `study` (làm lại để hiểu, không phải đi thi).
- "mua sách giáo trình" → `personal` (mua sắm), dù sách phục vụ việc học.
- "review code cho bạn" → `other` (giúp người khác, không phải bài của mình).
- "học thể dục" (môn ở trường) → `study`; "đi đá bóng" → `personal`.

Nhật ký sửa nhãn (ngày 2026-11-13, sau khi viết quy tắc):
- t006, a005 "họp nhóm đồ án": study → assignment
- a044 "meeting với nhóm": study → other
- a051 "push code lên GitHub trước năm giờ": other → assignment
