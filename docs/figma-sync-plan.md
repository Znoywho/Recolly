# Kế hoạch: Đồng bộ Figma ↔ Flutter (Hạo + Member 2)

Figma: https://www.figma.com/design/DJs4bjgsk3zHsFZv0wE6SX/Untitled
Quy tắc dịch Figma → Flutter: [figma-design-rules.md](figma-design-rules.md)

## Tiến độ
- [x] Hạo 1 — Variables (`Color` 13 biến, `Dimension` 12 biến), Text Styles `text/*` (7), Effect Style `shadow/hard` — 2026-11-25
- [~] Hạo 2 — bind layer vào Variables — 2026-11-25
  - [x] Màu: 2.310 fill/stroke trên 1.878 layer đã gắn `color/*` (chỉ màu khớp chính xác; bỏ qua layer trong instance)
  - [ ] Chữ: **chưa gán** `text/*` — chỉ 30/~700 đoạn chữ khớp đúng style. Figma dùng line-height `auto` gần hết, và có kiểu code không có: 15 SemiBold (82+), 13 Regular (27+), 20 ExtraBold (20). Cần Member 3 chốt: thêm style vào `AppTypography` hay sửa Figma theo code.
- [ ] Hạo 3 — component hóa + đổi tên
- [ ] Hạo 4 — Code Connect
- [ ] Hạo 5 — danh sách lệch từng màn
- [ ] Member 2 — bước 1–4 bên dưới

Màu lệch token đang có trong Figma (chưa gán biến, cần quyết định): `#E4DFD2` (27 lần, ≈ `skeleton #E5DFD2`), `#737373`, `#60635C`, `#E97373`, `#000000`, `#FFF5E4`, `#ADA99F`, `#535650`, `#C7CCD9`, `#F5C842`, `#F07070`, `#A8D5A2`, `#6BB259`, `#EDE8DE`.
Cỡ chữ ngoài thang `AppTypography`: 20 ExtraBold (20 lần), 44, 68, 36, 14, 16, 17.

## Context
File Figma `DJs4bjgsk3zHsFZv0wE6SX` có ~40 màn 393×852 nhưng **không có Variables**, chỉ 5 component (`Auth / Google`, `Auth / Text field`, `Auth / Primary button`, `Ô tích` ×2). Code Flutter đã có token (`client/lib/core/theme/`) và widget dùng chung (`client/lib/widgets/brutal_*.dart`). Hai bên chưa nói chung một "ngôn ngữ" → dịch Figma sang code dễ lệch màu/khoảng cách. Mục tiêu: Figma dùng đúng token của code, component Figma trỏ về widget Flutter, và có danh sách lệch từng màn để sửa.

Nguyên tắc chia việc (theo `.claude/CLAUDE.md`):
- **Hạo** làm phía **Figma** (không đụng `client/`).
- **Member 2** làm phía **code** trong các feature của mình.
- **Member 3** sở hữu `core/theme/`, `lib/widgets/`, và các màn today/sleep/welcome/personal → chỉ báo, không sửa hộ. Báo trước cho Member 3 vì Figma là task R53/R54 của họ.

## Người 1 — Hạo (Figma, qua Figma MCP)
1. **Variables** — tạo 2 collection trong Figma, tên khớp 1-1 với Dart:
   - `color/*` từ `AppColors` (`cream #EFEBE0, teal #9CC5C5, green #B0D980, coral #F0847A, yellow #F4D35E, white, ink #111111, inkMuted, slate, deepSlate, disabled, skeleton, danger`).
   - `spacing/*` (`xxs 4 … whitespace 100`), `radius/*` (`card 16, input 12, pill 999`), `border/width 2.5`.
   - Text Styles theo `AppTypography` (display 40/800, title 28/800, subtitle 18/800, body 15/400, label 13/600, caption 12/400, button 15/800; font Be Vietnam Pro).
   - Effect Style `shadow/hard` = ink, offset (0,4), blur 0.
2. **Bind** fill/stroke/text của các màn sang Variables; màu hex nào không khớp token → ghi vào danh sách lệch (bước 4), không tự thêm token.
3. **Component hóa** + đổi tên: tạo component `BrutalCard`, `BrutalButton`, `BrutalIconButton`, `BrutalBadge`, `BrutalProgressBar`, `BrutalBottomNavBar` (thay "Điều hướng nổi" vẽ lại ở mỗi màn), "Thanh trạng thái"; đổi tên `Group 4`, `Frame 2`, `Sack bar` → tên có nghĩa (vd `Snackbar`).
4. **Code Connect** (lưu trong Figma qua `add_code_connect_map`, không tạo file trong repo): map mỗi component ở bước 3 → `client/lib/widgets/brutal_*.dart`; `Auth / *` → `client/lib/features/auth/widgets/*`. Trước khi làm, kiểm tra Code Connect có nhận label Flutter không; nếu không, ghi mapping vào bảng trong tài liệu rules thay thế.
5. **Đối chiếu từng màn (đọc)**: với mỗi màn chạy `get_design_context` + `get_screenshot`, so với code, xuất **danh sách lệch** (màn, node-id, file:dòng, lệch gì, owner). Chia theo owner:
   - Member 2: auth, calendar, sync, todo, timetable/scan, voice.
   - Member 3: today/home, biorhythm, sleep, welcome/onboarding, personal, motivation popup, notifications.

## Người 2 — Member 2 (code trong feature của mình)
1. Nhận danh sách lệch phần của mình, sửa trong `client/lib/features/{auth,calendar,sync,todo,timetable}/` — thay `Color(0x…)`/số cứng bằng `AppColors`/`AppSpacing`/`AppRadii`, thay widget tự vẽ bằng `Brutal*` có sẵn.
   - Đã biết: `features/calendar/week_calendar_page.dart:20` `skeletonColor` → `AppColors.skeleton`.
2. Màn có trong Figma nhưng chưa có code (Voice_input 4 trạng thái, GCal "Chọn sự kiện"/"Kết quả đồng bộ"/"Xác nhận ngắt kết nối", "Ô tích") → build từ Figma theo `docs/figma-design-rules.md`, dùng Code Connect của bước 4 để lấy widget đúng.
3. Cần token/widget mới (vd checkbox `Ô tích`) → mở issue cho Member 3, không sửa `core/theme/` hay `lib/widgets/`.
4. Đọc `docs/figma-design-rules.md`; nếu muốn chuyển nó vào `client/` thì làm PR sau khi Member 3 duyệt.

## Thứ tự & phụ thuộc
```
Hạo 1 → 2 → 3 → 4 ─┐
Hạo 5 (song song từ khi xong 1) ─┴→ Member 2 bước 1–2
Member 2 bước 3–4 làm bất cứ lúc nào
```
Member 2 có thể bắt đầu ngay việc thay hằng số cứng bằng token có sẵn — không cần chờ Figma.

## Kiểm tra
- Figma: `get_variable_defs` trên vài màn trả về biến `color/*`, `spacing/*` (hiện đang trả `{}`); `get_code_connect_map` trả về đúng đường dẫn widget.
- Code: `cd client && flutter analyze && flutter test` (có golden trong `test/goldens/`); `grep -rn "Color(0x" client/lib/features` chỉ còn lại chỗ đã báo Member 3.
- Chạy app (`flutter run`), so mắt từng màn đã sửa với `get_screenshot`.
