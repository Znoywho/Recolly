import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../todo/todo_list_page.dart' show TodoChip, TopBar;
import 'edit_subject_sheet.dart';
import 'scan_result_page.dart';

// "Thêm môn học": add one subject by hand, laid out like "Thêm việc cần làm"
// (TodoFormPage) so both manual forms feel the same.
// Adds to the timetable (never replaces it). Pops `true` when saved.
class SubjectFormPage extends StatefulWidget {
  const SubjectFormPage({super.key});

  @override
  State<SubjectFormPage> createState() => _SubjectFormPageState();
}

class _SubjectFormPageState extends State<SubjectFormPage> {
  final nameCtrl = TextEditingController();
  final roomCtrl = TextEditingController();

  // 1 = Monday ... 7 = Sunday; one class session per ticked day.
  final Set<int> days = {};
  TimeOfDay start = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay end = const TimeOfDay(hour: 9, minute: 30);
  late DateTime firstDay = DateUtils.dateOnly(DateTime.now());
  late DateTime lastDay = firstDay.add(const Duration(days: 7 * 15));
  bool saving = false;

  @override
  void dispose() {
    nameCtrl.dispose();
    roomCtrl.dispose();
    super.dispose();
  }

  // Asks for a time; isStart picks which end of the class it sets.
  Future<void> pickTime(bool isStart) async {
    FocusScope.of(context).unfocus();
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? start : end,
    );
    if (t != null) setState(() => isStart ? start = t : end = t);
  }

  // Asks for the first and last day of the course.
  Future<void> pickRange() async {
    FocusScope.of(context).unfocus();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(firstDay.year - 1),
      lastDate: DateTime(firstDay.year + 2),
      initialDateRange: DateTimeRange(start: firstDay, end: lastDay),
    );
    if (range != null) {
      setState(() {
        firstDay = range.start;
        lastDay = range.end;
      });
    }
  }

  // The message to show, or null when the form can be saved.
  String? problem() {
    if (nameCtrl.text.trim().isEmpty) return 'Nhập tên môn trước nhé';
    if (days.isEmpty) return 'Chọn ít nhất một thứ trong tuần';
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      return 'Giờ kết thúc phải sau giờ bắt đầu';
    }
    return null;
  }

  Future<void> save() async {
    final error = problem();
    if (error != null) {
      showError(error);
      return;
    }
    final room = roomCtrl.text.trim();
    final drafts = [
      for (final day in days.toList()..sort())
        SubjectDraft(
          name: nameCtrl.text.trim(),
          room: room.isEmpty ? null : room,
          dayOfWeek: day,
          startTime: ClockTime(start.hour, start.minute),
          endTime: ClockTime(end.hour, end.minute),
          startDate: firstDay,
          endDate: lastDay,
        ),
    ];
    setState(() => saving = true);
    try {
      await RepositoryScope.of(context).timetable.saveSubjects(drafts);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => saving = false);
      showError('Không lưu được, thử lại nhé');
    }
  }

  void showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Same field label and tap box as TodoFormPage.
  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs, top: AppSpacing.md),
    child: Text(text, style: AppTypography.label),
  );

  Widget pickBox(String text, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.inputAll,
      child: InputDecorator(
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          suffixIcon: Icon(icon, size: 20),
        ),
        child: Text(text, maxLines: 1, style: AppTypography.body),
      ),
    );
  }

  // Start and end time side by side, like "Ngày hạn / Giờ hạn".
  Widget timeRow() {
    Widget half(String title, TimeOfDay t, bool isStart) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label(title),
          pickBox(
            '${two(t.hour)}:${two(t.minute)}',
            Icons.schedule,
            () => pickTime(isStart),
          ),
        ],
      ),
    );
    return Row(
      children: [
        half('Bắt đầu', start, true),
        const SizedBox(width: AppSpacing.sm),
        half('Kết thúc', end, false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            const TopBar(),
            const SizedBox(height: AppSpacing.lg),
            const Text('Thêm môn học', style: AppTypography.title),
            label('Tên môn'),
            TextField(controller: nameCtrl),
            label('Học thứ mấy (chọn nhiều được)'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (var day = 1; day <= 7; day++)
                  TodoChip(
                    label: shortDayName(day),
                    selected: days.contains(day),
                    onTap: () => setState(
                      () =>
                          days.contains(day) ? days.remove(day) : days.add(day),
                    ),
                  ),
              ],
            ),
            timeRow(),
            label('Phòng (không bắt buộc)'),
            TextField(controller: roomCtrl),
            label('Học kỳ'),
            pickBox(
              '${dateText(firstDay)} → ${dateText(lastDay)}',
              Icons.date_range,
              pickRange,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: BrutalButton(
                    label: 'Hủy',
                    color: AppColors.white,
                    onPressed: saving ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: BrutalButton(
                    label: saving ? 'Đang lưu...' : 'Lưu',
                    onPressed: saving ? null : save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
