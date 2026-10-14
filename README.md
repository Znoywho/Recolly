<div align="center">

# 🌿 RECOLLY

**Điều hòa lịch trình sinh hoạt cho sinh viên – cân bằng giữa học tập và nghỉ ngơi**

![Flutter](https://img.shields.io/badge/Mobile-Flutter-02569B?logo=flutter&logoColor=white) ![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL-4169E1?logo=postgresql&logoColor=white) ![Gemini](https://img.shields.io/badge/LLM-Google%20Gemini-8E75B2?logo=googlegemini&logoColor=white) ![License](https://img.shields.io/badge/License-MIT-green) ![Status](https://img.shields.io/badge/Status-In%20Development-orange)

</div>

---

## 📑 Mục lục

- [Giới thiệu](#-giới-thiệu)
- [Vấn đề & mục tiêu](#-vấn-đề--mục-tiêu)
- [Tính năng chính](#-tính-năng-chính)
- [Công nghệ sử dụng](#-công-nghệ-sử-dụng)
- [Kiến trúc hệ thống](#-kiến-trúc-hệ-thống)
- [Lộ trình triển khai](#-lộ-trình-triển-khai)
- [Cài đặt & chạy thử](#-cài-đặt--chạy-thử)
- [Thành viên nhóm](#-thành-viên-nhóm)
- [Giấy phép](#-giấy-phép)

---

## 📖 Giới thiệu

**Recolly** là ứng dụng di động giúp sinh viên tự động xếp lịch học, ôn thi và thời gian nghỉ ngơi theo **nhịp sinh học cá nhân**.

Người dùng chỉ cần chụp ảnh thời khóa biểu; Recolly trích xuất dữ liệu, ước tính mức tỉnh táo trong ngày, tự xếp giờ ôn thi – giờ nghỉ vào các khung giờ phù hợp và đưa lên Google Calendar.

**Đối tượng:** sinh viên học theo hệ tín chỉ.

---

## 🎯 Vấn đề & mục tiêu

### Vấn đề

- Học theo tín chỉ nên thời khóa biểu **thay đổi mỗi kỳ**; sinh viên thường phải **nhập thủ công** vào Google Calendar vì phần mềm của trường không đồng bộ được.
- Phải tự quản lý lịch sinh hoạt, lịch ôn thi và giờ ngủ.
- Khi lịch học dày, **giấc ngủ là thứ bị hy sinh đầu tiên** mà không có công cụ nào cảnh báo.

### Mục tiêu

1. Chụp ảnh thời khóa biểu → nhận lại lịch đã được chuẩn hóa.
2. Ước tính **nợ giấc ngủ** và **mức tỉnh táo** trong ngày bằng [mô hình hai quá trình điều hòa giấc ngủ của Borbély](https://www.chronobiology.ch/wp-content/uploads/2019/05/BorbélyJSR2016.pdf).
3. Tự xếp giờ ôn thi và giờ nghỉ vào khung giờ phù hợp, rồi đẩy lên Google Calendar.

---

## ✨ Tính năng chính

### 🗓️ Module 1: Đồng bộ lịch trình
Tích hợp Google Calendar để đồng bộ thời khóa biểu và các sự kiện.

### 😴 Module 2: Sleep Debt – Theo dõi nhịp sinh học
Ước lượng khả năng nhận thức, mức độ tập trung và tỉnh táo của người dùng suốt cả ngày dựa trên **Two-Process Model of Sleep Regulation** (Process S – áp lực ngủ, Process C – nhịp sinh học) của Borbély.

### 🔔 Module 3: Giao diện trực quan, nhắc nhở & động lực
- Nhắc giờ ngủ và các deadline sắp tới.
- Thông báo tiến độ học tập kèm các câu quote khích lệ sinh viên.

### 📸 Module 4: Nhập thời khóa biểu & lời nhắc nhanh
- Tải ảnh thời khóa biểu → hệ thống tự trích xuất và tạo lịch (OCR tiếng Việt với [Vintern-1B-v3_5](https://huggingface.co/5CD-AI/Vintern-1B-v3_5)).
- Nhập lời nhắc bằng giọng nói tiếng Việt (PhoWhisper).

---

## 🛠️ Công nghệ sử dụng

| Thành phần | Công nghệ |
|---|---|
| Mobile | Flutter |
| Backend | FastAPI (Python) |
| Cơ sở dữ liệu | PostgreSQL |
| Lịch | Google Calendar API (OAuth 2.0) |
| Xếp lịch tối ưu | OR-Tools CP-SAT |
| Nhận diện văn bản (OCR) | Vintern-1B-v3_5 |
| Nhận diện giọng nói (ASR) | PhoWhisper |
| LLM | Google Gemini |

---

## 🏗️ Kiến trúc hệ thống

```mermaid
flowchart LR
    A[📱 Flutter App] -->|REST API| B[⚙️ FastAPI Backend]
    B --> C[(🐘 PostgreSQL)]
    B --> D[📅 Google Calendar API]
    B --> E[🖼️ Vintern - OCR]
    B --> F[🎙️ PhoWhisper - ASR]
    B --> G[🤖 Google Gemini - LLM]
    B --> H[🧮 OR-Tools CP-SAT]
    B --> I[😴 Two-Process Model S/C]
```

---

## 🗺️ Lộ trình triển khai

### Giai đoạn 1 – Lõi hệ thống
- [ ] Xếp giờ ôn thi và giờ nghỉ bằng CP-SAT, dựa trên mô hình Process S/C đơn giản.
- [ ] Đẩy lịch lên Google Calendar (một chiều).
- [ ] Giải quyết ràng buộc khi đặt todo-list vào "thời gian vàng" và đối chiếu với thời khóa biểu.
- [ ] Chụp ảnh thời khóa biểu và trích xuất dữ liệu.
- [ ] Người dùng kiểm tra, chỉnh sửa kết quả trích xuất.

### Giai đoạn 2 – Mở rộng
- [ ] Thông báo nhắc giờ ngủ và deadline.
- [ ] Đồng bộ hai chiều với Google Calendar.
- [ ] Nhập bằng giọng nói (PhoWhisper).

### Giai đoạn 3 – Hoàn thiện
- [ ] Quote khích lệ bằng LLM (hoặc bộ câu có sẵn).

---

## 🚀 Cài đặt & chạy thử

### Yêu cầu

- Flutter SDK `>= 3.x`
- Python `>= 3.10`
- PostgreSQL `>= 14`
- Tài khoản Google Cloud (bật Calendar API, tạo OAuth 2.0 Client ID)
- API key Google Gemini

### 1. Clone dự án

```bash
git clone https://github.com/<username>/recolly.git
cd recolly
```

### 2. Chạy Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env            # điền DATABASE_URL, GEMINI_API_KEY, GOOGLE_CLIENT_ID...
uvicorn app.main:app --reload
```

API docs: `http://localhost:8000/docs`

### 3. Chạy Mobile

```bash
cd mobile
flutter pub get
flutter run
```

---

## 👥 Thành viên nhóm

| STT | Họ và tên | MSSV |
|:-:|---|:-:|
| 1 | Nguyễn Vũ Hoàng | 052206004253 |
| 2 | Cao Lê Huy Hoàng | 077206010722 |
| 3 | Lê Thiên Hạo | 089206010393 |

- **Giảng viên hướng dẫn:** Trương Quang Tuấn
- **Trường:** Đại học Giao thông Vận tải Thành phố Hồ Chí Minh
- **Môn:** Lập trình thiết bị di động
- **MHP:** 012012103403

---

## 📄 Giấy phép

Dự án được phát hành theo giấy phép MIT.

<div align="center">

⭐ Nếu thấy dự án hữu ích, hãy cho nhóm một **Star** nhé! ⭐

</div>
