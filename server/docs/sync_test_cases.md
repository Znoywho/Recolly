# Kịch bản test: đồng bộ Google Calendar, xếp lịch, todo & thông báo

Dùng cùng với `server/docs/calendar_sync.md` (thiết kế) và `server/docs/scheduler.md` (giờ vàng).
Đánh dấu cột **KQ**: ✅ đúng như mong đợi · ❌ sai (ghi lại bạn thấy gì) · ⏭ bỏ qua.

## 0. Chuẩn bị

1. `docker compose up -d --build`. Nếu muốn test chiều Google → app theo thời gian thực thì chạy thêm ngrok:
   `ngrok http 8765 --url <WEBHOOK_BASE_URL>`.
2. Mở app, **đăng nhập Google** (có quyền Calendar) và **làm hồ sơ giấc ngủ** (CP-SAT cần hồ sơ này).
3. Đặt alias để gõ lệnh lab cho nhanh (chạy trong thư mục `Recolly/`):
   ```bash
   lab() { docker exec -i recolly-server-container python - "$@" < server/scripts/sync_lab.py 2>&1 | grep -v OCR_PROVIDER; }
   ```
4. Mở thêm một terminal để xem log: `docker compose logs -f server | grep -iE "GCal|Auto push|webhook"`.

| Lệnh lab | Làm gì |
|---|---|
| `lab status` | trạng thái kết nối, chế độ, số `pending` và số conflict |
| `lab list [ngày]` | event trong app: id, giờ, loại, nguồn, `sync_status`, `G` = đã có bản trên Google |
| `lab google [ngày]` | event **thật sự có trên Google** (lịch đích) |
| `lab event add "<tên>" "YYYY-MM-DD HH:MM" [--minutes 60] [--kind study]` | tạo event, in ra trùng giờ và khối học bị dời |
| `lab event move <id> "YYYY-MM-DD HH:MM"` / `rename <id> "<tên>"` / `delete <id>` | sửa hoặc xoá |
| `lab todo add "<tên>" [--category exam] [--deadline "…"] [--estimate 90] [--at "…" --minutes 60]` | tạo todo |
| `lab todo done <id>` / `delete <id>` | xong hoặc xoá todo |
| `lab plan [ngày] [--apply]` | chạy CP-SAT, in focus/window/KSS của từng khối học; `--apply` để lưu |
| `lab sync` · `lab mode off/push/two_way` · `lab policy ask/google/local/latest` | sync tay, đổi chế độ, đổi chính sách |
| `lab conflicts` · `lab resolve <id> google/local` | xem và giải conflict |
| `lab reminders "YYYY-MM-DD HH:MM" [giờ]` | những thông báo **sẽ** được gửi trong khoảng đó (không gửi thật) |
| `lab cleanup` | xoá mọi thứ có tên bắt đầu bằng `[TEST]`, cả trên Google |

Id chỉ cần gõ 8 ký tự đầu. Mọi thứ lab tạo ra đều có tiền tố `[TEST]`.

---

## A. Kết nối & chế độ sync

| ID | Bước | Mong đợi | KQ |
|---|---|---|---|
| A1 | `lab status` ngay sau khi đăng nhập | `connected: true`, `sync_mode: push`, `calendar_id: primary` (thành lịch "Recolly" riêng khi app xin scope `calendar.app.created`, việc của Member 2) | |
| A2 | `lab mode off` → `lab event add "Tắt sync" "<ngày mai> 10:00"` → `lab list 2` → `lab google 2` | Trong app: `pending`, không có `G`. Trên Google: không có | |
| A3 | `lab sync` khi đang `off` | Lỗi `409 CALENDAR_SYNC_OFF` | |
| A4 | `lab mode push` → đợi 2–3 giây → `lab list 2` | Event "Tắt sync" thành `synced` + `G`, và có trên Google. Bạn không gõ `sync` | |
| A5 | `lab mode two_way` → `lab status` | `two_way_sync: true`. Log có `events/watch 200` nếu đã đặt `WEBHOOK_BASE_URL` | |

## B. Sửa

| ID | Bước | Mong đợi | KQ |
|---|---|---|---|
| B1 | `lab event add "Họp nhóm" "<ngày mai> 19:00"` | Trong vài giây: `synced`, có trên Google, log `GCal sync … pushed=1` | |
| B2 | `lab event rename <id> "Họp lớp"` | Tên trên Google đổi theo, không cần `sync` | |
| B3 | `lab event move <id> "<ngày mai> 20:00"` | Giờ trên Google đổi theo (giữ nguyên độ dài) | |
| B4 | **Chế độ push.** Trên Google, đổi tên event của B1 | `lab sync` → `pulled: 0`, app giữ tên cũ (một chiều) | |
| B5 | **two_way.** Trên Google, đổi tên event đó | Có webhook: log `webhook 200` rồi `GCal webhook pull … pulled=1`. Không có ngrok: `lab sync`. App có tên mới | |
| B6 | two_way. Trên Google, dời **một buổi** của lịch học (chọn "Chỉ sự kiện này") | `lab list 14`: buổi đó hiện ở giờ mới, giờ cũ biến mất. Thời khoá biểu trong app **không đổi** | |
| B7 | two_way. Trên Google, đổi giờ **cả chuỗi** lịch học ("Tất cả sự kiện") | Môn học trong thời khoá biểu đổi thứ/giờ theo | |

## C. Xoá

| ID | Bước | Mong đợi | KQ |
|---|---|---|---|
| C1 | `lab event delete <id>` | Biến mất trên Google trong vài giây | |
| C2 | two_way. Tạo event trong app, đợi nó lên Google, rồi **xoá trên Google** | Event bị xoá khỏi app sau khi pull | |
| C3 | two_way. **Xoá cả chuỗi lịch học trên Google** | Lịch học **vẫn còn** trong app (`not_synced`) và không tự tạo lại trên Google | |
| C4 | two_way. Xoá **một buổi** lịch học trên Google | Buổi đó biến mất trong app, các buổi khác giữ nguyên | |
| C5 | `lab todo add "Gặp thầy" --at "<ngày mai> 15:00"` → đợi lên Google → `lab todo delete <id>` | Event "Gặp thầy" bị xoá trên Google. Khối học (nếu có) vẫn giữ | |

## D. Sync lại & sửa trùng (cùng một event bị sửa ở hai nơi)

Để có "sửa ở cả hai phía trước khi sync", ta tạm tắt sync (`off`), sửa ở cả hai nơi, rồi bật lại.

| ID | Bước | Mong đợi | KQ |
|---|---|---|---|
| D1 | `lab sync` hai lần liên tiếp → `lab google 7` | Lần hai `pushed: 0`. Trên Google không có bản trùng | |
| D2 | two_way. `lab mode off` → `lab event rename <id> "Tên app"` → trên Google đổi **địa điểm** của event đó → `lab mode two_way` → `lab sync` | **Gộp**, không có conflict: tên = "Tên app", địa điểm = của Google, ở cả hai nơi | |
| D3 | `lab policy ask` → `off` → đổi tên trong app "A" → đổi tên trên Google "B" → `two_way` → `lab sync` | `conflicts: 1`. `lab conflicts` hiện A và B. `lab resolve <id> local` → Google thành "A" trong vài giây (tự đẩy) | |
| D4 | Lặp D3 với `lab policy google` | Không có conflict, cả hai thành "B" | |
| D5 | Lặp D3 với `lab policy local` | Không có conflict, cả hai thành "A" | |
| D6 | Lặp D3 với `lab policy latest`, sửa trên Google **sau** khi sửa trong app | Thành "B" (bên sửa sau cùng thắng) | |

## E. Trùng giờ & tự xếp lại

| ID | Bước | Mong đợi | KQ |
|---|---|---|---|
| E1 | `lab event add "Làm thêm" "<ngày mai> 18:00" --minutes 180` → `lab event add "Họp" "<ngày mai> 19:00"` | Lệnh thứ hai in `⚠ trùng giờ: [TEST] Làm thêm … (recolly)`. Không có gì bị dời | |
| E2 | `lab todo add "Ôn thi" --category exam --deadline "<3 ngày nữa> 09:00" --estimate 90` → `lab plan 3 --apply` → `lab list 3` để lấy giờ của khối học → `lab event add "Họp CLB" "<giờ khối học>"` | In `↪ khối học dời sang …`. Khối cũ biến mất trên Google, khối mới xuất hiện, không đè lên "Họp CLB" | |
| E3 | two_way. Lặp E2 nhưng tạo "Họp CLB" **trên Google** đè lên khối học | Sau pull: khối học được dời trong app và trên Google (⚠ xem lỗi H2 nếu pull chạy bằng job bảo trì) | |
| E4 | Chế độ push, lịch đích là "Recolly" (sau khi có scope). Tạo một event cá nhân trên lịch chính Google, rồi `lab event add` đè lên giờ đó | In `⚠ trùng giờ: <tên event Google> (google)` | |
| E5 | Như E4, rồi chạy `lab plan 3` | Không có khối học nào rơi vào giờ của event Google đó | |

## F. Xếp lịch có hợp lý không (giờ vàng)

| ID | Bước | Mong đợi | KQ |
|---|---|---|---|
| F1 | `lab todo add "Ôn thi" --category exam --deadline "<2 ngày nữa> 22:00" --estimate 90` và `lab todo add "Nộp form" --deadline "<2 ngày nữa> 22:00" --estimate 45` → `lab plan 2` | "Ôn thi": `focus=high window=golden`. "Nộp form": `focus=light window=low`. KSS của "Ôn thi" thấp hơn | |
| F2 | So với màn **Biorhythm** trong app cùng ngày | Giờ của "Ôn thi" nằm trong khung giờ vàng mà màn Biorhythm hiển thị | |
| F3 | Tạo 4 todo `exam`, mỗi cái 90 phút, cùng deadline sau 2 ngày → `lab plan 2` | Tối đa **2 khối khó/ngày**; phần còn lại báo `HARD_LIMIT_REACHED` hoặc dời sang ngày khác | |
| F4 | Tạo event cố định chiếm hết giờ vàng của ngày mai → F1 lại | "Ôn thi" có `window=normal`: giờ vàng đã kín, app nên giải thích điều này | |
| F5 | `lab todo add "Không hạn" --estimate 60` → `lab plan 3` | `chưa xếp được …: MISSING_DEADLINE` | |
| F6 | `lab todo add "Không ước tính" --deadline "<2 ngày nữa> 22:00"` → `lab plan 3` | `MISSING_ESTIMATE` | |
| F7 | `lab todo add "Gấp" --deadline "<1 giờ nữa>" --estimate 60` → `lab plan 1` | `NOT_ENOUGH_TIME_BEFORE_DEADLINE` (khối học phải xong trước deadline 120 phút) | |

## G. Todo có giờ / không giờ / deadline: hiển thị và thông báo

Thông báo mặc định: nhắc deadline **trước 24 giờ và 2 giờ**; **15 phút trước** khi khối học hoặc todo có giờ bắt đầu; và nhắc đi ngủ.

| ID | Todo | Lên lịch (app + Google)? | Thông báo (`lab reminders …`) | KQ |
|---|---|---|---|---|
| G1 | Không giờ, không deadline | Không | Không có | |
| G2 | Có deadline `D` | **Không** có event; chỉ có khối học sau khi `plan --apply` | `reminders "<D − 24h>" 1` → "Còn 24 giờ: …"; `reminders "<D − 2h>" 1` → "Còn 2 giờ: …" | |
| G3 | Có giờ cố định (`--at`) | **Có**, 1 event cùng giờ, có kiểm tra trùng giờ | `event_start` "15 phút nữa: …" trước giờ bắt đầu 15 phút | |
| G4 | G2 rồi `lab todo done <id>` | — | `reminders` không còn báo todo đó | |
| G5 | G3 rồi `lab todo done <id>` | Event của todo bị xoá trên Google | — | |
| G6 | Đặt giờ yên lặng (quiet hours) trong app, ví dụ 23:00–07:00, cho deadline rơi vào khung đó | — | Thông báo trong giờ yên lặng bị bỏ | |
| G7 | `lab todo add "Bài tập" --category assignment` | — | `difficulty=5` (mặc định theo category); `other`/`personal` → 1, `study` → 3 | |

## H. Các lỗi đã sửa (2026-11-28): kiểm lại xem có còn không

| ID | Tình huống | Mong đợi sau khi sửa | KQ |
|---|---|---|---|
| H1 | `lab mode off`, rồi lưu lịch CP-SAT với `sync_to_google: true` (luồng đẩy lịch của app) | Lưu thành công, khối học ở `pending`; `lab mode push` thì chúng tự lên Google | |
| H2 | two_way, **tắt ngrok**, thêm event trên Google đè lên khối học, rồi `docker compose restart calendar-maintenance` | Job kéo về, dời khối học, và **khối mới lên Google** (không cần sửa thêm gì) | |
| H3 | D2 nhưng **không** gõ `lab sync` ở cuối, đợi vài giây | Bản gộp tự lên Google, event ở `synced` | |
| H4 | Có scope lịch riêng: ngắt kết nối trong app rồi kết nối lại | Lịch "Recolly" cũ **bị xoá** khi ngắt; sau khi kết nối lại chỉ có **một** lịch "Recolly" | |
| H5 | two_way. Trên Google thêm 2–3 event cùng lúc, mỗi cái đè lên một khối học, rồi `lab sync` | Tất cả khối học được dời trong **một** lần chạy CP-SAT (log chỉ có một dòng `solve`) | |
| H6 | `lab todo add "Gặp thầy" --at "<ngày mai> 15:00"` → `lab reminders "<ngày mai> 14:40" 1` | `event_start 15 phút nữa: [TEST] Gặp thầy`. Khối học từ `lab plan --apply` cũng được nhắc như vậy | |

Ghi chú H6: nhắc trước **15 phút**, bật/tắt chung với công tắc nhắc deadline (chưa có cài đặt riêng).
H4: ngắt kết nối xoá lịch "Recolly" cùng các bản sao trên đó (trong app vẫn giữ nguyên). Lịch do người dùng
tự chọn (G8) thì Google không cho app xoá, nên luôn được giữ lại.

## Dọn dẹp

`lab cleanup`, và trên Google thì xoá tay những gì bạn tạo trực tiếp ở đó.
