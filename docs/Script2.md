RECOLLY
Recolly điều hòa lịch trình sinh hoạt cho sinh viên, cân bằng giữa việc học và nghỉ ngơi

I.

TỔNG QUAN

Recolly là ứng dụng di động giúp cho sinh viên tự xếp lịch học, ôn thi và thời gian nghỉ ngơi theo

nhịp sinh học cá nhân

Giải quyết: Sinh viên học theo tín chỉ thì thay đổi theo từng kỳ, thường phải nhập thủ công vào vào
Google calendar để có thể đồng bộ phần mềm của trường. Và cũng phải tự quản lí lịch sinh hoạt, ôn thi,
giờ ngủ. Khi lịch học dày, giấc ngủ là thứ bị hy sinh đầu tiên mà không có công cụ nào cảnh báo.

Mục tiêu: Người dùng chụp ảnh thời khóa biểu và nhận lại lịch đã chuẩn hóa. Hệ thống ước tính nợ
giấc ngủ cùng mức tỉnh táo trong ngày bằng mô hình hai quá trình điều hòa giấc ngủ của Borbély, sau
đó tự xếp giờ ôn thi và giờ nghỉ vào các khung giờ phù hợp và đưa lên Google Calendar.

II.

Các tính năng chính:

• Module 1: Đồng bộ lịch trình - Tích hợp Google calendar để đồng bộ thời khỏa biểu và các sự

kiện

• Module 2: Sleep debt - Theo dõi Nhịp sinh học: Khả năng nhận thức, mức độ tập trung và tỉnh
táo của người dùng duy trì mức độ tĩnh trong suốt cả ngày (Sử dụng Two-process of sleep
regulation của Borbély)

• Module 3: Giao diện trực quan và thông báo nhắc nhở người dùng và động lực cho sinh viên.
Sinh viên sẽ luôn được nhắc nhở việc giấc ngủ và các deadline sắp tới và thông báo tiến độ hộ
học nhầm khích lệ sinh viên bằng các câu quote

• Module 4: Nhập thời khoá biểu và lời nhắc nhanh chóng. Cho phép người dùng nhập các ảnh

thời khóa biểu xuất dữ liệu ra các lịch trình khóa biểu tự động
◦ Mô hình nhận diện văn bản tiếng việt Vintern-1B-v3_5
◦ Nhận biết giọng nói: PhoWhisper
Công nghệ sử dụng

III.

• Mobile:Flutter
• Backend: FastAPI (Python)
• Database: PostgreSQL
• Lịch: Google Calendar API (OAuth 2.0)
• Xếp lịch: OR-Tools CP-SAT
• AI/ NLP/ CV: Vintern, PhoWhisper (ASR), Google Gemini (LLM)

IV.

Các giai đoạn triển khai:

Giai đoạn 1:

• Xếp giờ ôn thi và nghỉ bằng CP-SAT, dựa trên mô hình Process S/C đơn giản.
• Đẩy lịch lên Google Calendar theo một chiều.
• Giải quyết các ràng buộc khi thực hiện todo-list cho mỗi thời gian vàng và so sánh với thời

khóa biểu

• Chụp ảnh thời khóa biểu và trích xuất dữ liệu.
• Người dùng kiểm tra, chỉnh lại kết quả.

Giai đoạn 2:

• Thông báo nhắc giấc ngủ và deadline.
• Đồng bộ hai chiều với Google Calendar.
• Nhập bằng giọng nói (PhoWhisper).

Giai đoạn 3:

• LLM quote (hoặc dùng bản câu có sẵn, đơn giản).

