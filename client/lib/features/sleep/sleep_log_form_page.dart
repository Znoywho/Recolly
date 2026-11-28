import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../timetable/edit_subject_sheet.dart' show dateText, two;
import '../todo/todo_list_page.dart' show TodoChip, TopBar;

// R34 "Ghi giấc ngủ": one night (or a nap), laid out like "Thêm việc cần làm".
// Pops `true` when saved.
class SleepLogFormPage extends StatefulWidget {
  const SleepLogFormPage({super.key});

  @override
  State<SleepLogFormPage> createState() => _SleepLogFormPageState();
}

// Server limits (server/app/schemas/health.py): MAX_SLEEP_HOURS, FUTURE_SKEW.
const maxSleepHours = 16;
const futureSkew = Duration(minutes: 5);

const qualityNames = ['Rất tệ', 'Tệ', 'Bình thường', 'Tốt', 'Rất tốt'];

// Bedtime and wake time as full dates, given the day the user woke up.
// A bedtime later than the wake time was the evening before (23:30 → 07:00);
// otherwise it is the same day (00:30 → 07:00, or a nap 13:00 → 14:00).
(DateTime, DateTime) sleepWindow(
  DateTime wakeDay,
  TimeOfDay bed,
  TimeOfDay wake,
) {
  final wakeAt = DateTime(
    wakeDay.year,
    wakeDay.month,
    wakeDay.day,
    wake.hour,
    wake.minute,
  );
  var sleepAt = DateTime(
    wakeDay.year,
    wakeDay.month,
    wakeDay.day,
    bed.hour,
    bed.minute,
  );
  if (!sleepAt.isBefore(wakeAt)) {
    sleepAt = sleepAt.subtract(const Duration(days: 1));
  }
  return (sleepAt, wakeAt);
}

// The message to show, or null when the server will accept this night.
String? sleepProblem(DateTime sleepAt, DateTime wakeAt, DateTime now) {
  if (wakeAt.difference(sleepAt) > const Duration(hours: maxSleepHours)) {
    return 'Một lần ngủ tối đa $maxSleepHours giờ, kiểm tra lại giờ nhé';
  }
  if (wakeAt.isAfter(now.add(futureSkew))) {
    return 'Giờ thức dậy chưa tới, kiểm tra lại ngày nhé';
  }
  return null;
}

class _SleepLogFormPageState extends State<SleepLogFormPage> {
  final noteCtrl = TextEditingController();
  // Before 07:00 the default 07:00 wake time would be in the future.
  DateTime wakeDay = DateUtils.dateOnly(
    DateTime.now().subtract(const Duration(hours: 7)),
  );
  TimeOfDay bed = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay wake = const TimeOfDay(hour: 7, minute: 0);
  int? quality;
  bool saving = false;

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> pickDay() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: wakeDay,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now,
    );
    if (d != null) setState(() => wakeDay = d);
  }

  // isBed picks which of the two times is set.
  Future<void> pickTime(bool isBed) async {
    FocusScope.of(context).unfocus();
    final t = await showTimePicker(
      context: context,
      initialTime: isBed ? bed : wake,
    );
    if (t != null) setState(() => isBed ? bed = t : wake = t);
  }

  Future<void> save() async {
    final (sleepAt, wakeAt) = sleepWindow(wakeDay, bed, wake);
    final problem = sleepProblem(sleepAt, wakeAt, DateTime.now());
    if (problem != null) {
      showError(problem);
      return;
    }
    final note = noteCtrl.text.trim();
    setState(() => saving = true);
    try {
      await RepositoryScope.of(context).sleep.createSleepLog(
        SleepLogCreate(
          sleepAt: sleepAt,
          wakeAt: wakeAt,
          quality: quality,
          note: note.isEmpty ? null : note,
        ),
      );
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

  // One half of the "Đi ngủ / Thức dậy" row.
  Widget timeHalf(String title, TimeOfDay t, bool isBed) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(title),
        pickBox(
          '${two(t.hour)}:${two(t.minute)}',
          Icons.schedule,
          () => pickTime(isBed),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final (sleepAt, wakeAt) = sleepWindow(wakeDay, bed, wake);
    final slept = wakeAt.difference(sleepAt);
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
            const Text('Ghi giấc ngủ', style: AppTypography.title),
            label('Ngày thức dậy'),
            pickBox(dateText(wakeDay), Icons.calendar_today_outlined, pickDay),
            Row(
              children: [
                timeHalf('Đi ngủ lúc', bed, true),
                const SizedBox(width: AppSpacing.sm),
                timeHalf('Thức dậy lúc', wake, false),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Bạn ngủ ${slept.inHours} giờ ${two(slept.inMinutes % 60)} phút '
              '(từ ${two(sleepAt.day)}/${two(sleepAt.month)}).',
              style: AppTypography.body,
            ),
            label('Ngủ có ngon không? (không bắt buộc)'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (var q = 1; q <= 5; q++)
                  TodoChip(
                    label: qualityNames[q - 1],
                    selected: quality == q,
                    // Tapping the picked one again clears it.
                    onTap: () =>
                        setState(() => quality = quality == q ? null : q),
                  ),
              ],
            ),
            label('Ghi chú (không bắt buộc)'),
            TextField(controller: noteCtrl, maxLength: 500),
            const SizedBox(height: AppSpacing.md),
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
