# Pipeline giọng nói → todo — kiến trúc

> Owner: Backend — Member 1 (R42, R43). Phía Flutter: Member 2 (R41, R44).
> Ghi ngày 2026-11-23, theo code trên `main`. Hợp đồng API: `V1 POST /voice/transcribe`, `V2 GET /voice/jobs/{id}` trong [`openapi.yaml`](openapi.yaml).

## 1. Tóm tắt

1. **Lưu ghi âm trước, xử lý sau.** File âm thanh và một dòng `voice_jobs` được commit trước khi gọi Kaggle, nên Kaggle tắt cũng không mất ghi âm.
2. **ASR + LLM chạy trên Kaggle GPU**, server gọi qua 2 tunnel Cloudflare (PhoWhisper-medium và Ollama `qwen2.5:14b`).
3. **Deadline do luật tính, không do LLM.** LLM chỉ sửa lỗi nghe, đặt tên, chọn category/priority; `VietnameseTimeParser` đọc ngày giờ từ câu đã sửa.
4. **Server không tự lưu todo.** Nó trả về bản nháp (`todo_draft`); app cho người dùng xác nhận rồi mới gọi API todo.
5. **Kaggle tắt → 202 + hàng đợi.** `voice-worker` thử lại mỗi phút, xong thì push `voice_ready` qua FCM.

## 2. Sơ đồ thành phần

```mermaid
flowchart LR
    APP["📱 Flutter App<br/>ghi âm .m4a"]

    subgraph SERVER["⚙️ server (FastAPI)"]
        API["voice_api.py<br/>POST /voice/transcribe<br/>GET /voice/jobs/{id}"]
        JOBS["voice_jobs.py<br/>create_job · process_job"]
        ASRC["transcriber.py<br/>PhoWhisperTranscriber"]
        TODO["todo_parser.py<br/>VoiceTodoParser"]
        TIME["time_parser.py<br/>VietnameseTimeParser (luật)"]
    end

    subgraph WORKER["🔁 voice-worker (mỗi phút)"]
        PV["jobs/process_voice.py<br/>thử lại · bỏ cuộc sau 24h · xoá sau 7 ngày"]
    end

    subgraph KAGGLE["☁️ Kaggle GPU (qua tunnel Cloudflare)"]
        PHO["PhoWhisper-medium<br/>POST /transcribe"]
        OLL["Ollama qwen2.5:14b<br/>POST /api/chat"]
    end

    DB[("🐘 PostgreSQL<br/>voice_jobs")]
    VOL[("💾 volume voice-audio<br/>/data/voice")]
    FCM["Firebase Cloud Messaging"]

    APP -->|multipart: audio, reference_time| API
    API --> JOBS
    JOBS -->|ghi file| VOL
    JOBS -->|dòng job| DB
    JOBS --> ASRC -->|file âm thanh| PHO
    JOBS --> TODO -->|câu nói| OLL
    TODO --> TIME
    JOBS -.->|Ollama lỗi: chỉ dùng luật| TIME

    PV -->|job queued| JOBS
    PV -->|voice_ready| FCM -.-> APP
    PV -->|xoá file + job cũ| VOL
```

## 3. Một request đi qua những bước nào

```mermaid
sequenceDiagram
    autonumber
    participant App as Flutter App
    participant API as voice_api
    participant Jobs as voice_jobs
    participant DB as PostgreSQL + volume
    participant ASR as PhoWhisper (Kaggle)
    participant LLM as Ollama (Kaggle)
    participant TP as time_parser

    App->>API: POST /voice/transcribe (audio, reference_time)
    API->>API: kiểm tra rỗng / ≤ 25 MB / đuôi file
    API->>Jobs: create_job
    Jobs->>DB: ghi file + dòng job (status=processing), commit
    API->>Jobs: process_job (trong threadpool)
    Jobs->>ASR: gửi file âm thanh
    alt Kaggle tắt (AsrUnavailable)
        Jobs->>DB: status=queued
        API-->>App: 202 {job_id, status}
    else File hỏng (AsrRejected)
        Jobs->>DB: status=failed, VOICE_BAD_AUDIO
        API-->>App: 422
    else Nghe được
        ASR-->>Jobs: transcript
        Jobs->>LLM: transcript + lịch 21 ngày tới
        alt Ollama chạy
            LLM-->>Jobs: corrected_transcript, title, category, priority
        else Ollama lỗi
            Note over Jobs: draft_from_rules_only (parser = "rules")
        end
        Jobs->>TP: extract_deadline(câu đã sửa, reference_time)
        TP-->>Jobs: deadline_at (+07:00) hoặc null
        Jobs->>DB: result + status=succeeded
        API-->>App: 200 TranscribeResponse
    end
```

Khi nhận 202, app hỏi lại `GET /voice/jobs/{job_id}` hoặc chờ push `voice_ready`.

## 4. Trạng thái của một voice job

```mermaid
stateDiagram-v2
    [*] --> processing: create_job
    processing --> succeeded: nghe + nháp xong
    processing --> failed: file hỏng (VOICE_BAD_AUDIO)
    processing --> queued: Kaggle tắt
    queued --> processing: voice-worker nhận job (≤ 5 job/phút)
    processing --> processing: kẹt > 10 phút → worker nhận lại
    queued --> failed: chờ quá 24h (VOICE_ASR_UNAVAILABLE)
    succeeded --> [*]: push voice_ready (nếu qua worker)
    succeeded --> [*]: xoá sau 7 ngày
    failed --> [*]: xoá sau 7 ngày
```

## 5. Ai làm gì

| Bước | File | Ghi chú |
|---|---|---|
| Nhận file, kiểm tra | `server/app/api/voice_api.py` | Tối đa 25 MB; chỉ `.m4a .mp4 .aac .wav .ogg .mp3` được giữ đuôi |
| Lưu + xử lý job | `server/app/service/voice/voice_jobs.py` | Commit trước khi gọi Kaggle; log chỉ ghi độ dài câu, không ghi nội dung |
| Speech-to-text | `server/app/service/voice/transcriber.py` | `ASR_BASE_URL`, `ASR_TOKEN`, timeout 120s |
| Sửa câu + nháp todo | `server/app/service/voice/todo_parser.py` | `VOICE_LLM_MODEL` (mặc định `qwen2.5:14b`), `VOICE_REPAIR_TRANSCRIPT=1` |
| Đọc ngày giờ | `server/app/service/voice/time_parser.py` | "tối thứ sáu", "chiều mai", "9 giờ tối" → giờ +07:00; chỉ có ngày → 23:59 |
| Thử lại, push, dọn dẹp | `server/app/jobs/process_voice.py` | Service `voice-worker` trong `docker-compose.yml` |

## 6. Số liệu đo thật (2026-11-23, 14 lần gửi)

| | ASR | LLM | Tổng |
|---|---|---|---|
| Câu ngắn (27–107 ký tự) | 1.4–3.5s | 3.7–5.2s | 5–9s |
| Đoạn văn (121–258 ký tự) | 3–5s | 4–6s | 7–11s |
| Đoạn dài (696 ký tự) | 15.6s | 10.3s | 26s |
| Lần đầu (Kaggle chưa nóng) | 10.4s | 7.4s | 18s |

LLM là phần chậm nhất. Xem log từng bước trong Dozzle (container `recolly-server-container`, `recolly-voice-worker-container`).

## 7. Giới hạn đã biết

- `estimated_minutes` và `difficulty` luôn `null`: chưa có bước nào trích "hai tiếng", "một tiếng rưỡi".
- Câu không phải lệnh (đọc một đoạn văn) vẫn sinh ra `todo_draft`.
- Tên todo đôi khi lấy nguyên câu lệnh ("Đặt Lịch Học"), viết hoa không thống nhất.
