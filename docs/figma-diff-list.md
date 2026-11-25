# Danh sách lệch Figma ↔ token (2026-11-25)

Quét tự động toàn bộ 38 frame trên Figma (bỏ qua layer trong instance và màu logo Google).
"Lệch" = màu không khớp `AppColors` hoặc kiểu chữ không nằm trong `AppTypography`.
Mở node: `https://www.figma.com/design/DJs4bjgsk3zHsFZv0wE6SX/Untitled?node-id=<id, ":" → "-">`.

Chỉ đối chiếu ở mức token, chưa so pixel từng màn với app chạy thật.

## Quyết định chung (Member 3 chốt — sở hữu `core/theme/`)
| Lệch | Số chỗ trong Figma | Trong code | Đề xuất |
|---|---|---|---|
| Chữ **20 ExtraBold** (tiêu đề màn) | ~25 màn | chỉ 2 chỗ `fontSize: 20` | thêm `AppTypography.heading` 20/800 **hoặc** Figma đổi sang `title` 28 |
| Chữ **15 SemiBold** | 80+ | 2 chỗ `semiBold` copyWith | thêm `AppTypography.bodyStrong` 15/600 |
| Chữ **13 Regular** | 35+ | — | thêm `AppTypography.small` 13/400 hoặc đổi sang `caption` 12 |
| Chữ 44 ExtraBold (số lớn: 72%, 4h 10p) | 3 | `fontSize: 36/32/30/70` rải rác | thêm `AppTypography.metric` |
| Màu `#E4DFD2` (skeleton) | 27 | `week_calendar_page.dart:20` cũng dùng `0xFFE4DFD2` | đổi `AppColors.skeleton` thành `#E4DFD2` (khớp cả Figma lẫn code) |
| Màu `#E97373` (đỏ nhạt, nút xóa/lỗi) | 9 | — | dùng `coral` hoặc thêm token |
| Màu `#737373` (chữ phụ xám) | 17 | — | đổi sang `inkMuted #5C5A55` |
| `#C7CCD9`, `#ADA99F`, `#535650`, `#60635C`, `#000000`, `#6BB259`, `#EDE8DE` | 1–4 mỗi màu | — | gộp vào token gần nhất (`disabled`, `inkMuted`, `ink`, `green`, `cream`) |

## Member 2 (Cao Lê Huy Hoàng)
| Màn Figma | node | Code | Lệch |
|---|---|---|---|
| Đăng nhập | 251:2 | `features/auth/screen/login_screen.dart` | `#ADA99F`×2, `#535650`, `#60635C`; chữ 15 SemiBold×2, 13 Regular×2, 14 Regular, 16 SemiBold |
| Đăng ký | 251:5 | `features/auth/screen/register_screen.dart` | `#ADA99F`×2, `#535650`×3; chữ 36 ExtraBold, 15 SemiBold, 13 Regular×2, 12 SemiBold |
| Lịch tuần | 12:1925 | `features/calendar/week_calendar_page.dart` | 13 Regular×1; code `:20` `skeletonColor` tự định nghĩa |
| Lịch tuần – Đang tải | 114:131 | như trên | `#E4DFD2`×8, 13 Regular |
| Lịch tuần – Trống | 114:295 | như trên | 20 ExtraBold, 15 SemiBold, 13 Regular |
| Chi tiết sự kiện | 12:2080 | `features/calendar/event_detail_page.dart` | 13 Regular, 15 SemiBold×2 |
| Sửa môn học | 5:1329 | `features/timetable/edit_subject_sheet.dart` | 20 ExtraBold, 15 SemiBold×3 |
| Scanning result | 2:1374 | `features/timetable/scan_result_page.dart` | 20 ExtraBold, 15 SemiBold×5 |
| Việc cần làm | 308:33 | `features/todo/todo_list_page.dart` | `#737373`×5, `#E97373`, `#EDE8DE`; 20 ExtraBold, 15 SemiBold×6, 13 Regular×4 |
| Cá nhân | 18:749 | `features/personal/personal_page.dart` | `#E97373`, 15 SemiBold |
| GCal – Đã kết nối | 273:33 | `features/sync/google_calendar_sheet.dart` | `#E97373`, 15 SemiBold×3 |
| GCal – Chưa kết nối | 273:140 | như trên | `#E97373`, 15 SemiBold×2, 17 Regular |
| GCal – Chọn sự kiện | 317:33 | **chưa có code** | `#737373`×5, `#C7CCD9`; 20 ExtraBold, 13 Regular×5, 15 SemiBold×8 |
| GCal – Kết quả đồng bộ | 317:177 | **chưa có code** | `#737373`×2, `#C7CCD9`; 20 ExtraBold, 13 Regular×3, 15 SemiBold×5 |
| GCal – Đồng bộ thành công | 328:33 | **chưa có code** | `#737373`×2, `#C7CCD9`; 13 Regular×3, 15 SemiBold×5, 20 SemiBold |
| GCal – Xác nhận ngắt kết nối | 331:51 | **chưa có code** | `#E97373`, `#000000`×4; 15 SemiBold×3, 20 Bold, 16 Bold×2 |
| Voice_input (+ 4 trạng thái) | 5:1272, 298:33/91/149/207 | **chưa có code** | `#737373`, `#E97373`, `#6BB259`; 20 ExtraBold, 15 SemiBold×2 mỗi màn |
| Nhập thời khóa biểu | 1:2 | `features/timetable/timetable_import_page.dart` | không lệch |

## Member 3 (Nguyễn Vũ Hoàng) — chỉ báo
| Màn Figma | node | Code | Lệch |
|---|---|---|---|
| Trang chủ | 9:1262 | `features/today/today_page.dart` | 44 ExtraBold, 13 Regular, 20 ExtraBold |
| Trang chủ – Đang tải | 114:3 | `features/today/widgets/today_skeleton.dart` | `#E4DFD2`×19 |
| Lỗi mạng | 114:555 | `features/today/widgets/load_error_card.dart` | 20 ExtraBold, 15 SemiBold |
| Nhịp sinh học | 9:1362 | `features/today/biorhythm_page.dart` | 15 SemiBold, 13 Regular×7, 20 ExtraBold |
| Popup động lực | 18:664 | `features/today/widgets/motivation_dialog.dart` | 15 SemiBold, 44 ExtraBold, 20 ExtraBold |
| Giấc ngủ | 16:670 | `features/sleep/sleep_page.dart` | 44 ExtraBold, 15 SemiBold |
| Giấc ngủ – Trống | 114:465 | `features/sleep/widgets/sleep_empty_card.dart` | 20 ExtraBold, 15 SemiBold |
| Thông báo | 16:750 | **chưa có code** (R38) | 13 Regular×4 |
| Việc cần làm – Thêm / Sửa | 308:150 | `features/todo/todo_form_page.dart` (R57) | `#E97373`, 20 ExtraBold, 15 SemiBold×2 |
| Schedual_scanning-screen | 210:2 | `features/timetable/scan_page.dart` (R62) | `#000000`, 20 ExtraBold, 20 Bold, 15 SemiBold |
| scan failed | 5:1394 | **chưa có code** (R62) | 20 ExtraBold, 15 SemiBold×2 |
| Splash | 1:183 | `features/welcome_screens/logoscreen.dart` | `#2D2D2D`×12, `#FFF5E4`×4, `#F5C842`×2, `#F07070`×2, `#A8D5A2` (minh họa logo — có thể giữ), 68 ExtraBold |
| Code (không có trong Figma) | — | `features/today/widgets/barchat.dart:252,259` | `Color(0xFFE88B73)` hardcode |
