import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

// R58: event detail bottom sheet over the week calendar
// (Figma "Chi tiết sự kiện" 12:2080).
// "Sửa" moves the event to a new day/start time (same length), "Xóa" deletes it.
// Class sessions and repeating events are view only (the API edits the whole
// series). show() returns 'moved' or 'deleted' when something changed.

class EventDetailSheet extends StatefulWidget {
  const EventDetailSheet({
    super.key,
    required this.event,
    required this.repo,
    this.golden = false,
  });

  final CalendarEvent event;
  final EventRepository repo;

  // Event overlaps a golden-hour window of that day
  final bool golden;

  static Future<String?> show(
    BuildContext context, {
    required CalendarEvent event,
    required EventRepository repo,
    bool golden = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.ink.withValues(alpha: 0.22),
      builder: (_) =>
          EventDetailSheet(event: event, repo: repo, golden: golden),
    );
  }

  @override
  State<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<EventDetailSheet> {
  bool busy = false;

  CalendarEvent get event => widget.event;

  bool get canEdit =>
      event.kind != EventKind.classSession && event.rrule == null;

  static String two(int n) => n.toString().padLeft(2, '0');

  static String hhmm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  static const weekdayLongNames = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];

  // Source tag text + color
  (String, Color) sourceTag() => switch (event.source) {
    EventSource.scheduler => ('Do AI xếp', AppColors.green),
    EventSource.ocr => ('Thời khóa biểu', AppColors.white),
    EventSource.google => ('Google Calendar', AppColors.teal),
    EventSource.manual => ('Tự thêm', AppColors.white),
  };

  void showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // Pick a new day + start time, keep the same length.
  Future<void> move() async {
    final start = event.startAt.toLocal();
    final length = event.endAt.difference(event.startAt);
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null || !mounted) return;
    final newStart = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => busy = true);
    try {
      await widget.repo.updateEvent(
        event.id,
        EventUpdate(startAt: newStart, endAt: newStart.add(length)),
      );
      if (!mounted) return;
      Navigator.pop(context, 'moved');
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      showSnack('Không dời được, thử lại nhé.');
    }
  }

  Future<void> delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa sự kiện này?'),
        content: Text(event.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repo.deleteEvent(event.id);
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      showSnack('Không xóa được, thử lại nhé.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();
    final (sourceText, sourceColor) = sourceTag();
    return Container(
      width: double.infinity,
      decoration: AppTheme.brutalBox(
        color: AppColors.cream,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
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
              const SizedBox(height: AppSpacing.lg),
              Text(event.title, style: AppTypography.title),
              const SizedBox(height: AppSpacing.sm),
              infoRow(
                Icons.schedule,
                '${hhmm(start)} - ${hhmm(end)}, '
                '${weekdayLongNames[start.weekday - 1]}',
              ),
              if (event.location != null) ...[
                const SizedBox(height: AppSpacing.xs),
                infoRow(Icons.place_outlined, 'Phòng ${event.location}'),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 10,
                runSpacing: AppSpacing.sm,
                children: [
                  tag(sourceText, sourceColor),
                  if (widget.golden) tag('Giờ vàng', AppColors.yellow),
                  if (event.rrule != null) tag('Hằng tuần', AppColors.white),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Ghi chú', style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 80),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: AppTheme.brutalBox(
                  color: AppColors.white,
                  borderRadius: AppRadii.cardAll,
                ),
                child: Text(
                  event.description ?? 'Chưa có ghi chú',
                  style: AppTypography.body.copyWith(
                    height: 1.4,
                    color: event.description == null
                        ? AppColors.inkMuted
                        : AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (canEdit)
                Row(
                  children: [
                    Expanded(
                      child: BrutalButton(
                        label: 'Sửa',
                        icon: Icons.edit_outlined,
                        leadingIcon: true,
                        color: AppColors.white,
                        onPressed: busy ? null : move,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: BrutalButton(
                        label: 'Xóa',
                        icon: Icons.delete_outline,
                        leadingIcon: true,
                        color: AppColors.coral,
                        onPressed: busy ? null : delete,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  event.kind == EventKind.classSession
                      ? 'Tiết học sửa trong thời khóa biểu nhé.'
                      : 'Sự kiện lặp lại chưa sửa được ở đây.',
                  style: AppTypography.label.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.ink),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppTypography.body)),
      ],
    );
  }

  // Pill tag with hard shadow (Figma "Nhãn sự kiện")
  Widget tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: AppTheme.brutalBox(
        color: color,
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(text, style: AppTypography.label),
    );
  }
}
