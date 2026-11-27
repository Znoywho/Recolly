import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../timetable/subject_form_page.dart';
import '../timetable/timetable_import_page.dart';
import '../todo/todo_form_page.dart';
import '../todo/todo_list_page.dart';
import '../voice/voice_input_page.dart';

// "Thêm lịch" sheet opened by the "+" in the nav bar: the one place to add a
// todo or a timetable, by voice, photo (OCR) or by hand.
// Resolves to true when something was saved, so the caller can reload.
Future<bool> showAddScheduleSheet(BuildContext context) async {
  final navigator = Navigator.of(context);
  final page = await showModalBottomSheet<Widget>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: AppBorders.side,
    ),
    builder: (_) => const AddScheduleSheet(),
  );
  // The sheet only picks a page; it is pushed after the sheet has closed.
  if (page == null) return false;
  final saved = await navigator.push(MaterialPageRoute(builder: (_) => page));
  return saved == true;
}

class AddScheduleSheet extends StatefulWidget {
  const AddScheduleSheet({super.key});

  @override
  State<AddScheduleSheet> createState() => _AddScheduleSheetState();
}

class _AddScheduleSheetState extends State<AddScheduleSheet> {
  // "Nhập tay" shows two more choices instead of opening a page.
  bool manualOpen = false;

  // Closes the sheet and hands the chosen page to showAddScheduleSheet.
  void open(Widget page) => Navigator.pop(context, page);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Thêm lịch', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Chọn cách nhanh nhất với bạn.',
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.md),
            option(
              icon: Icons.mic_none,
              color: AppColors.teal,
              title: 'Nói',
              subtitle: 'Nói một câu, máy tạo việc và deadline',
              onTap: () => open(const VoiceInputPage()),
            ),
            option(
              icon: Icons.photo_camera_outlined,
              color: AppColors.yellow,
              title: 'Chụp thời khóa biểu',
              subtitle: 'Chụp ảnh lịch học, máy đọc ra các môn',
              onTap: () => open(const TimetableImportPage()),
            ),
            option(
              icon: Icons.edit_outlined,
              color: AppColors.white,
              title: 'Nhập tay',
              subtitle: 'Tự điền việc cần làm hoặc môn học',
              onTap: () => setState(() => manualOpen = !manualOpen),
            ),
            if (manualOpen)
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  TodoChip(
                    label: 'Việc / deadline',
                    selected: false,
                    onTap: () => open(const TodoFormPage()),
                  ),
                  TodoChip(
                    label: 'Môn học',
                    selected: false,
                    onTap: () => open(const SubjectFormPage()),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // One big tappable row: icon, title, one line of help.
  Widget option({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: BrutalCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                BrutalIconTile(
                  icon: icon,
                  color: color,
                  size: 48,
                  iconSize: 24,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.subtitle),
                      Text(subtitle, style: AppTypography.body),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
