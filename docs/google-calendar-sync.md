# Đồng bộ Google Calendar — ghi chú thiết kế

> Trạng thái: **đề xuất**, chưa đưa vào `openapi.yaml` (xem §9).
> Owner: Backend — Member 1 (R30, R31, R45). Phía Flutter: Member 2 (R32, R33, R46).
> Ghi ngày 2026-10-22. Số liệu Google lấy từ tài liệu chính thức (§11).

## 1. Tóm tắt quyết định

1. **PostgreSQL của Recolly là nguồn dữ liệu chính.** Flutter chỉ gọi API Recolly, không bao giờ gọi Google Calendar trực tiếp.
2. **Kết nối lần đầu kéo toàn bộ sự kiện về** (full sync); những lần sau chỉ kéo phần thay đổi (`syncToken`).
3. **Ghi lên Google bằng hàng đợi chạy nền** (outbox). Giao diện không bao giờ chờ Google.
4. **Webhook (push notification) thay cho polling.**
5. **Lịch phụ "Recolly"**: app chỉ ghi vào lịch này; lịch chính của người dùng chỉ đọc.
6. **Không nhúng WebView** Google Calendar.

## 2. Vì sao không nhúng WebView

- Google chặn đăng nhập OAuth trong WebView nhúng (lỗi `disallowed_useragent`).
- WebView chỉ để xem: không nối được với todo, bộ xếp lịch CP-SAT hay mô hình giấc ngủ.
- Không kiểm soát được giao diện (Neo-brutalism) và không dùng offline được.

## 3. Rate limit

| Giới hạn (Calendar API) | Con số |
|---|---|
| Mỗi user, mỗi phút | 600 request |
| Cả project, mỗi phút | 10.000 request |
| Cả project, mỗi ngày | 1.000.000 request |

Vượt giới hạn mỗi phút → HTTP `403` hoặc `429` với lý do `usageLimits`. Google tính theo cửa sổ trượt,
nên một đợt gọi dồn dập có thể bị chặn sang cả phút sau.

**Ước lượng cho 1 sinh viên:**

| Việc | Request |
|---|---|
| Kết nối lần đầu: kéo sự kiện (tối đa 2.500 sự kiện/trang) | 1–3 |
| Đẩy thời khóa biểu: 1 môn = 1 sự kiện lặp (RRULE) cho cả học kỳ | ~10 |
| Áp lịch học một tuần (S2) | ~10–15 |
| Mỗi lần kéo thay đổi bằng `syncToken` | 1 |

→ Dưới 100 request/ngày/người, so với giới hạn 600/**phút**. Rate limit chỉ thành vấn đề khi:
- polling liên tục ("có gì mới không?" mỗi phút cho mọi user), hoặc
- gọi Google ngay trong request của người dùng (bấm một cái là gọi Google một cái).

Thiết kế dưới đây tránh cả hai.

## 4. Kiến trúc

```
📱 Flutter: cache trên máy + cập nhật lạc quan
   │  E1–E5, D1–D5, S2 … (API Recolly: nhanh, không dính rate limit Google)
   ▼
🖥  Server Recolly ── PostgreSQL (nguồn chính)
   │      ▲
   │      │ kéo thay đổi (syncToken) khi có webhook / mở app / định kỳ
   │ đẩy  │
   ▼      │
☁️  Google Calendar
     ├─ Lịch chính của user  → chỉ đọc (hiện trên lịch tuần + làm giờ bận cho CP-SAT)
     └─ Lịch phụ "Recolly"   → đọc/ghi (lớp học, khối học, giờ ngủ do app tạo)
```

## 5. Scope OAuth

| Scope | Dùng để | Thay cho |
|---|---|---|
| `openid email profile` | Đăng nhập | — |
| `https://www.googleapis.com/auth/calendar.app.created` | Tạo lịch phụ "Recolly" và sửa sự kiện **trong lịch đó** | `calendar.events` (sửa được **mọi** lịch) |
| `https://www.googleapis.com/auth/calendar.events.readonly` | Đọc sự kiện lịch chính | — |

Scope hẹp hơn giúp người dùng yên tâm khi cấp quyền, và Google duyệt app dễ hơn.
Khi demo: để OAuth consent screen ở chế độ **Testing** và thêm Gmail của cả nhóm vào danh sách test users.

## 6. Các luồng

### 6.1 Kết nối lần đầu (A1 có scope Calendar, hoặc G6)

1. Đổi `server_auth_code` lấy token; lưu refresh token **đã mã hóa**.
2. Tạo lịch phụ "Recolly" (`calendars.insert`), lưu `recolly_calendar_id`. Nếu kết nối lại mà lịch cũ còn thì dùng lại; người dùng đã xóa thì tạo mới.
3. **Full sync lịch chính** (`events.list` trên `primary`):
   - `maxResults=2500`, `singleEvents=false` (lưu sự kiện lặp dạng chuỗi + RRULE; server tự bung ra khi trả E1), `timeMin` = 30 ngày trước.
   - Lặp theo `pageToken` tới trang cuối, lưu `nextSyncToken`.
   - Sự kiện lặp bị sửa riêng một buổi trả về thành sự kiện riêng có `recurringEventId` → lưu như ngoại lệ của chuỗi.
4. Đẩy các sự kiện đã có trong Recolly (lớp học từ TKB, khối học đã áp) lên lịch "Recolly".
5. Đăng ký webhook (`events.watch`) cho cả lịch chính và lịch "Recolly".
6. `import_status = done`. Flutter xem tiến độ qua G1.

### 6.2 Kéo thay đổi từ Google (incremental sync)

**Khi nào chạy:**
- Webhook G5 báo `X-Goog-Resource-State: exists`;
- Người dùng mở app hoặc kéo để làm mới (`POST /calendar/sync`, server gộp các yêu cầu cách nhau < 1 phút);
- Dự phòng định kỳ ~15 phút ± 25 % ngẫu nhiên (Google khuyên dàn đều thời điểm gọi).

**Cách gọi:** `events.list(syncToken=…)`, lặp `pageToken` tới khi có `nextSyncToken` mới thì lưu lại.
- **Không được** gửi kèm `syncToken`: `timeMin`, `timeMax`, `q`, `orderBy`, `updatedMin`, `iCalUID`, `privateExtendedProperty`, `sharedExtendedProperty` (Google trả `400`). Lọc theo thời gian thì làm ở server.
- Các tham số còn lại (`singleEvents`…) phải **giống hệt** lần full sync.

**Xử lý từng sự kiện:**
- `status = cancelled` → xóa bản local.
- Còn lại → upsert theo `google_event_id`, lưu `etag` mới.

**Token hết hạn (`410 Gone`):** xóa toàn bộ sự kiện local của lịch đó rồi full sync lại từ đầu, không dùng `syncToken`.

### 6.3 Đẩy thay đổi lên Google (outbox)

1. Người dùng tạo/sửa/xóa → ghi DB, đặt `sync_status = pending`, thêm một dòng vào `sync_queue`. API trả về **ngay**.
2. Worker chạy nền mỗi vài giây:
   - **Gộp lệnh:** nhiều lần sửa cùng một sự kiện chỉ đẩy trạng thái cuối cùng (sửa 5 lần = 1 request).
   - **Tạo mới:** `events.insert` vào lịch "Recolly" với `id = uuid.hex` của sự kiện. Google cho tự đặt id (chữ `a–v`, số `0–9`, dài 5–1024, khuyên dùng UUID), và UUID dạng hex hợp lệ.
     Nếu lần gửi trước bị lỗi mạng (không biết Google đã nhận chưa): gọi `events.get(id)` trước. Có rồi thì coi như thành công, chưa có mới `insert` lại. Google **không cam kết** báo lỗi khi trùng id, nên phải tự kiểm tra như vậy để **không tạo trùng**.
   - **Sửa/xóa:** gửi header `If-Match: <etag>`. Nhận `412` nghĩa là bên Google đã đổi → xem §6.4.
3. Lỗi `403`/`429` (`usageLimits`): chờ `min(2^n giây + ngẫu nhiên ≤ 1000 ms, 32–64 giây)` rồi thử lại, có giới hạn số lần; quá giới hạn thì `sync_status = error`.
4. Thành công → `sync_status = synced`, lưu `etag`, `last_synced_at`.
5. Lớp học từ TKB: **1 môn = 1 sự kiện lặp** (RRULE tới hết học kỳ), không đẩy từng buổi.

### 6.4 Xung đột (R45)

- Chỉ xảy ra với sự kiện trong **lịch "Recolly"** khi bật `two_way_sync`. Lịch chính chỉ đọc nên không bao giờ xung đột.
- Xung đột = local còn thay đổi chưa đẩy (`pending`) **và** `etag` bên Google đã khác lần đồng bộ trước.
- Khi đó tạo `SyncConflict`, đặt `sync_status = conflict`, gửi push `sync_conflict`. Người dùng chọn giữ bản nào qua G3 → G4.

### 6.5 Webhook (G5) và gia hạn kênh

- URL phải là **HTTPS với chứng chỉ hợp lệ** (không dùng chứng chỉ tự ký được).
- Body luôn **rỗng**: chỉ báo "có thay đổi", server phải tự gọi incremental sync.
- Kiểm tra `X-Goog-Channel-Token`, tìm kênh theo `X-Goog-Channel-ID`, bỏ qua `X-Goog-Resource-State: sync` (tin chào khi mới tạo kênh).
- Trả `200` ngay, đẩy job vào hàng đợi. Gộp nhiều thông báo của cùng một kênh trong ~5 giây thành một lần sync.
- Kênh **không tự gia hạn**: job hằng ngày tìm kênh sắp hết hạn trong 24 h → gọi `watch` lại với `id` mới, rồi `channels.stop` kênh cũ (hai kênh được phép chồng nhau một lúc).

### 6.6 Ngắt kết nối (G7)

1. `channels.stop` mọi kênh, thu hồi refresh token.
2. Xóa bản local của các sự kiện kéo từ lịch chính.
3. Sự kiện của Recolly giữ lại, chuyển `sync_status = not_synced`.
4. Lịch "Recolly" trên Google giữ nguyên; người dùng tự xóa nếu muốn.

## 7. Phía Flutter (Member 2)

- **Cache trên máy** (vd. `drift`/SQLite): mở màn hình là vẽ ngay từ cache, sau đó mới gọi E1 để cập nhật.
- **Cập nhật lạc quan:** tạo/sửa thì hiện ngay, gửi API ở nền, lỗi thì hoàn tác và báo người dùng.
- **Tự sinh UUID v4** cho sự kiện/todo mới, gửi kèm trong E2/D2 (cần sửa contract, §9) → gửi lại không bị trùng, dùng được khi mất mạng.
- Hiện biểu tượng theo `sync_status`: `pending` ⏳, `synced` ✓, `conflict` ⚠, `error` ✕.
- Kéo để làm mới → `POST /calendar/sync`.
- **Không bao giờ** gọi Google Calendar API trực tiếp từ app.

## 8. Dữ liệu cần lưu (server)

**`calendar_connections`** (1 dòng / user): `google_email`, `refresh_token_encrypted`, `scopes`, `recolly_calendar_id`, `two_way_sync`, `import_status`, `last_synced_at`.

**`calendar_sync_states`** (1 dòng / lịch được đồng bộ): `calendar_id`, `role` (`primary_readonly` | `recolly`), `sync_token`, `channel_id`, `channel_resource_id`, `channel_token`, `channel_expiration`.

**`events`**: thêm `calendar_id`, `read_only`; đã có sẵn `google_event_id`, `google_etag`, `sync_status`, `last_synced_at`.

**`sync_queue`**: `event_id`, `google_event_id`, `op` (`insert` | `update` | `delete`), `attempts`, `next_attempt_at`, `last_error`.
Phải là bảng riêng vì khi xóa sự kiện thì dòng trong `events` đã mất, nhưng vẫn phải nhớ để xóa bên Google.

## 9. Thay đổi hợp đồng API cần làm (chưa áp dụng)

- **A1 / G6:** đổi scope sang `calendar.app.created` + `calendar.events.readonly`. G6 kích hoạt full sync lần đầu (chạy nền).
- **G1 `CalendarStatus`:** thêm `import_status` (`importing` | `done` | `error`) và `recolly_calendar_id`.
- **`Event`:** thêm `read_only` (`true` với sự kiện từ lịch chính, E4/E5 trả `403`) và `calendar_id`.
- **E2 / D2:** cho phép gửi kèm `id` (UUID v4 do client sinh); gửi lại cùng `id` thì trả bản đã có, không tạo trùng.
- **G8:** bỏ đổi `calendar_id` tùy ý vì app luôn ghi vào lịch "Recolly"; giữ `two_way_sync`.

## 10. Môi trường dev

- Webhook cần HTTPS công khai: khi demo dùng tunnel (vd. `cloudflared`); lúc code ở local thì tắt webhook, dùng sync khi mở app + định kỳ.
- Client ID/secret và khóa mã hóa refresh token để trong `.env`, **không commit**.

## 11. Tài liệu tham khảo

- [Manage quotas](https://developers.google.com/workspace/calendar/api/guides/quota): 600/phút/user, 10.000/phút/project, backoff.
- [Choose scopes](https://developers.google.com/workspace/calendar/api/auth): `calendar.app.created`, `calendar.events.readonly`.
- [Synchronize resources efficiently](https://developers.google.com/workspace/calendar/api/guides/sync): `syncToken`, `410 Gone`.
- [Events: list](https://developers.google.com/workspace/calendar/api/v3/reference/events/list): tham số không dùng chung với `syncToken`, `maxResults` ≤ 2500.
- [Push notifications](https://developers.google.com/workspace/calendar/api/guides/push): HTTPS, body rỗng, gia hạn kênh.
- [Resource versions (ETag)](https://developers.google.com/workspace/calendar/api/guides/version-resources): `If-Match`, `412`.
