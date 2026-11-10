# Kịch bản thu âm tập test — 60 câu

Cách thu:
- Mỗi câu một file, nói tự nhiên như đang ra lệnh cho app (không đọc đều đều như đọc bài).
- Đặt tên file `<speaker>_<id>.m4a`, ví dụ `s01_a003.m4a`.
- Chia đều 3 người, mỗi người 20 câu (cột "Người đọc"), nhóm câu nào cũng có đủ 3 giọng:
  - `s01`: câu có số chia hết cho 3 (a003, a006, …, a060)
  - `s02`: câu có số chia 3 dư 1 (a004, a007, …, a061)
  - `s03`: câu có số chia 3 dư 2 (a005, a008, …, a062)
- Muốn nhiều clip hơn: mỗi người đọc thêm phần của người kế tiếp (s01 đọc thêm phần s02,
  s02 đọc thêm phần s03, s03 đọc thêm phần s01) → 120 clip, mỗi câu có 2 giọng.
- Nói vấp / nói sai chữ thì thu lại; còn tiếng ồn nền thì cứ để, đó là điều kiện dùng thật.
- Số được viết bằng chữ vì `transcript_gold` cũng viết bằng chữ.

Đã có sẵn trong `voice_eval.jsonl`: a001, a002.

## 1. Chỉ có giờ — `time_only` (15)

| id | Người đọc | Câu đọc |
|---|---|---|
| a003 | s01 | đặt lịch mới học xác suất lúc bảy giờ tối |
| a004 | s02 | đặt lịch mới chạy bộ lúc năm giờ rưỡi sáng |
| a005 | s03 | đặt lịch mới họp nhóm đồ án lúc ba giờ rưỡi chiều |
| a006 | s01 | đặt lịch mới ôn tiếng Anh lúc chín giờ tối |
| a007 | s02 | đặt lịch mới đi thư viện lúc tám giờ sáng |
| a008 | s03 | đặt lịch mới học lập trình lúc mười chín giờ ba mươi |
| a009 | s01 | đặt lịch mới làm bài tập toán rời rạc lúc mười giờ đêm |
| a010 | s02 | đặt lịch mới gọi điện cho mẹ lúc tám giờ kém mười lăm tối |
| a011 | s03 | đặt lịch mới ngủ trưa lúc mười hai giờ rưỡi |
| a012 | s01 | nhắc tui học bài lúc bốn giờ chiều |
| a013 | s02 | mười một giờ trưa đi ăn cơm với nhóm |
| a014 | s03 | sáu giờ chiều đi đá bóng |
| a015 | s01 | thêm việc giặt đồ lúc chín giờ sáng |
| a016 | s02 | tạo lịch đọc sách lúc mười giờ mười lăm tối |
| a017 | s03 | ba giờ chiều lên văn phòng khoa nộp đơn |

## 2. Ngày tương đối — `relative_date` (15)

| id | Người đọc | Câu đọc |
|---|---|---|
| a018 | s01 | đặt lịch mới ngày mai nộp báo cáo thực hành |
| a019 | s02 | đặt lịch mới thứ năm tuần này thi giữa kỳ vật lý |
| a020 | s03 | đặt lịch mới chủ nhật này đi học nhóm lúc chín giờ sáng |
| a021 | s01 | đặt lịch mới thứ hai tuần sau nộp đồ án môn học |
| a022 | s02 | đặt lịch mới ngày mốt kiểm tra mười lăm phút đại số |
| a023 | s03 | đặt lịch mới tối nay làm xong bài tập về nhà |
| a024 | s01 | đặt lịch mới sáng mai bảy giờ học thể dục |
| a025 | s02 | đặt lịch mới thứ bảy tuần sau thi cuối kỳ triết học |
| a026 | s03 | ba ngày nữa nộp bài tiểu luận |
| a027 | s01 | cuối tuần này dọn phòng trọ |
| a028 | s02 | thứ tư tuần sau lúc hai giờ chiều thuyết trình nhóm |
| a029 | s03 | hai tuần nữa hết hạn đăng ký học phần |
| a030 | s01 | chiều mai bốn giờ lên gặp thầy hướng dẫn |
| a031 | s02 | tuần sau thứ ba đóng học phí |
| a032 | s03 | tối thứ sáu này tám giờ ôn thi với bạn |

## 3. Không có deadline — `no_deadline` (10)

| id | Người đọc | Câu đọc |
|---|---|---|
| a033 | s01 | đặt lịch mới mua sách giáo trình |
| a034 | s02 | đặt lịch mới ôn lại chương ba giải tích |
| a035 | s03 | đặt lịch mới đọc tài liệu trí tuệ nhân tạo |
| a036 | s01 | đặt lịch mới làm lại bài kiểm tra bị sai |
| a037 | s02 | đặt lịch mới học thuộc từ vựng tiếng Nhật |
| a038 | s03 | nhớ mua vở và bút bi |
| a039 | s01 | cần hỏi thầy về điểm giữa kỳ |
| a040 | s02 | thêm việc đăng ký câu lạc bộ lập trình |
| a041 | s03 | tìm tài liệu tham khảo cho tiểu luận |
| a042 | s01 | sửa lại sơ yếu lý lịch xin thực tập |

## 4. Chen tiếng Anh — `code_switch` (10)

| id | Người đọc | Câu đọc |
|---|---|---|
| a043 | s02 | đặt lịch mới deadline đồ án web là thứ sáu |
| a044 | s03 | đặt lịch mới meeting với nhóm lúc tám giờ tối |
| a045 | s01 | đặt lịch mới làm slide thuyết trình môn marketing |
| a046 | s02 | đặt lịch mới ôn midterm môn OOP vào tối mai |
| a047 | s03 | đặt lịch mới review code cho bạn lúc ba giờ chiều |
| a048 | s01 | tối nay fix bug cho project Flutter |
| a049 | s02 | ngày mai submit bài lab môn machine learning |
| a050 | s03 | thứ năm này có quiz môn database |
| a051 | s01 | chiều mai push code lên GitHub trước năm giờ |
| a052 | s02 | cuối tuần này học online khóa Python |

## 5. Tên môn học / thuật ngữ — `domain_term` (10)

| id | Người đọc | Câu đọc |
|---|---|---|
| a053 | s03 | đặt lịch mới học xác suất thống kê lúc bảy giờ sáng |
| a054 | s01 | đặt lịch mới ôn cấu trúc dữ liệu và giải thuật tối nay |
| a055 | s02 | đặt lịch mới làm bài tập đại số tuyến tính |
| a056 | s03 | đặt lịch mới thứ tư thi kiến trúc máy tính |
| a057 | s01 | đặt lịch mới học nguyên lý hệ điều hành lúc một giờ chiều |
| a058 | s02 | ngày mai nộp bài tập lớn mạng máy tính |
| a059 | s03 | thứ sáu kiểm tra tư tưởng Hồ Chí Minh |
| a060 | s01 | tối mai ôn chủ nghĩa xã hội khoa học |
| a061 | s02 | làm báo cáo phân tích thiết kế hệ thống |
| a062 | s03 | chín giờ sáng mai học kinh tế chính trị Mác Lê nin |
