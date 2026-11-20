import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

// R14: "Sửa môn học" bottom sheet.
// Pops with the edited SubjectDraft, or EditSubjectSheet.delete.

const dayNames = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];

// 1 = Monday ... 7 = Sunday
String dayName(int day) => dayNames[day - 1];

String two(int n) => n.toString().padLeft(2, '0');

String dateText(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

Future<Object?> showEditSubjectSheet(
  BuildContext context,
  SubjectDraft subject, {
  bool isNew = false,
}) {
  return showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: AppBorders.side,
    ),
    builder: (_) => EditSubjectSheet(subject: subject, isNew: isNew),
  );
}

class EditSubjectSheet extends StatefulWidget {
  const EditSubjectSheet({
    super.key,
    required this.subject,
    this.isNew = false,
  });

  static const delete = 'delete';

  final SubjectDraft subject;
  final bool isNew;

  @override
  State<EditSubjectSheet> createState() => _EditSubjectSheetState();
}

class _EditSubjectSheetState extends State<EditSubjectSheet> {
  final nameCtrl = TextEditingController();
  final roomCtrl = TextEditingController();
  late int day;
  late ClockTime start;
  late ClockTime end;
  late DateTime startDate;
  late DateTime endDate;
  String? error;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    nameCtrl.text = s.name;
    roomCtrl.text = s.room ?? '';
    day = s.dayOfWeek;
    start = s.startTime;
    end = s.endTime;
    startDate = s.startDate;
    endDate = s.endDate;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    roomCtrl.dispose();
    super.dispose();
  }

  Future<void> pickTime(bool isStart) async {
    final old = isStart ? start : end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: old.hour, minute: old.minute),
    );
    if (t == null) return;
    setState(() {
      if (isStart) {
        start = ClockTime(t.hour, t.minute);
      } else {
        end = ClockTime(t.hour, t.minute);
      }
    });
  }

  Future<void> pickDate(bool isStart) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d == null) return;
    setState(() {
      if (isStart) {
        startDate = d;
      } else {
        endDate = d;
      }
    });
  }

  void save() {
    final name = nameCtrl.text.trim();
    String? msg;
    if (name.isEmpty) {
      msg = 'Nhập tên môn trước nhé';
    } else if (end.compareTo(start) <= 0) {
      msg = 'Giờ kết thúc phải sau giờ bắt đầu';
    } else if (endDate.isBefore(startDate)) {
      msg = 'Ngày kết thúc phải sau ngày bắt đầu';
    }
    // Show the error inside the sheet (a SnackBar is hidden behind it)
    if (msg != null) {
      setState(() => error = msg);
      return;
    }

    final room = roomCtrl.text.trim();
    final old = widget.subject;
    // confidence is dropped: the user checked this row
    Navigator.pop(
      context,
      SubjectDraft(
        name: name,
        code: old.code,
        room: room.isEmpty ? null : room,
        lecturer: old.lecturer,
        dayOfWeek: day,
        startTime: start,
        endTime: end,
        startDate: startDate,
        endDate: endDate,
        color: old.color,
      ),
    );
  }

  Widget pickBox(String text, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.inputAll,
      child: InputDecorator(
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          suffixIcon: Icon(icon, size: 18),
          suffixIconConstraints: const BoxConstraints(minWidth: 32),
        ),
        // Keep dates like 07/09/2026 on one line
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text, maxLines: 1, style: AppTypography.body),
        ),
      ),
    );
  }

  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs, top: AppSpacing.md),
    child: Text(text, style: AppTypography.label),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: AppRadii.pillAll,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isNew ? 'Thêm môn học' : 'Sửa môn học',
                    style: AppTypography.title,
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: AppTheme.brutalBox(
                    color: AppColors.yellow,
                    borderRadius: AppRadii.pillAll,
                  ),
                  child: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ),
            label('Tên môn'),
            TextField(controller: nameCtrl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Phòng'),
                      TextField(controller: roomCtrl),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Thứ'),
                      InputDecorator(
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: day,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            style: AppTypography.body,
                            items: [
                              for (var d = 1; d <= 7; d++)
                                DropdownMenuItem(
                                  value: d,
                                  child: Text(dayName(d)),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => day = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Giờ bắt đầu'),
                      pickBox(
                        start.toJson(),
                        Icons.schedule,
                        () => pickTime(true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Giờ kết thúc'),
                      pickBox(
                        end.toJson(),
                        Icons.schedule,
                        () => pickTime(false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Từ ngày'),
                      pickBox(
                        dateText(startDate),
                        Icons.calendar_today_outlined,
                        () => pickDate(true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Đến ngày'),
                      pickBox(
                        dateText(endDate),
                        Icons.calendar_today_outlined,
                        () => pickDate(false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                error!,
                style: AppTypography.label.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: BrutalButton(
                    label: 'Hủy',
                    color: AppColors.white,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: BrutalButton(label: 'Lưu', onPressed: save),
                ),
              ],
            ),
            if (!widget.isNew) ...[
              const SizedBox(height: AppSpacing.md),
              BrutalButton(
                label: 'Xóa môn này',
                icon: Icons.delete_outline,
                leadingIcon: true,
                color: AppColors.coral,
                onPressed: () =>
                    Navigator.pop(context, EditSubjectSheet.delete),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
