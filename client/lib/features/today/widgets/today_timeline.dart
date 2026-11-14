import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../today_format.dart';

class TimelineEntry {
  const TimelineEntry({
    required this.time,
    required this.title,
    required this.color,
    this.foregroundColor = AppColors.ink,
    this.badge,
    this.isDeadline = false,
  });

  factory TimelineEntry.fromEvent(CalendarEvent event) {
    final (color, foreground) = switch (event.kind) {
      EventKind.study => (AppColors.green, AppColors.ink),
      EventKind.rest => (AppColors.teal, AppColors.ink),
      EventKind.bedtime => (AppColors.slate, AppColors.white),
      EventKind.classSession ||
      EventKind.other => (AppColors.white, AppColors.ink),
    };
    return TimelineEntry(
      time: event.startAt,
      title: event.title,
      color: color,
      foregroundColor: foreground,
      badge: event.source == EventSource.scheduler ? 'AI xếp' : null,
    );
  }

  factory TimelineEntry.fromDeadline(Todo todo) => TimelineEntry(
    time: todo.deadlineAt!,
    title: todo.title,
    color: AppColors.coral,
    isDeadline: true,
  );

  final DateTime time;
  final String title;
  final Color color;
  final Color foregroundColor;
  final String? badge;
  final bool isDeadline;

  static List<TimelineEntry> forDay(HomeOverview overview) {
    bool isSameDay(DateTime time) =>
        time.year == overview.date.year &&
        time.month == overview.date.month &&
        time.day == overview.date.day;

    return [
      for (final event in overview.todayEvents)
        if (!event.allDay) TimelineEntry.fromEvent(event),
      for (final todo in overview.upcomingTodos)
        if (todo.deadlineAt != null && isSameDay(todo.deadlineAt!))
          TimelineEntry.fromDeadline(todo),
    ]..sort((a, b) => a.time.compareTo(b.time));
  }
}

class TodayTimeline extends StatelessWidget {
  const TodayTimeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const BrutalCard(
        borderStyle: BrutalBorderStyle.dashed,
        hasShadow: false,
        color: AppColors.cream,
        child: Text(
          'Hôm nay chưa có lịch nào. Nhập thời khóa biểu hoặc thêm todo để Recolly xếp lịch cho bạn.',
          style: AppTypography.body,
        ),
      );
    }
    return Column(
      children: [
        for (final (index, entry) in entries.indexed)
          _TimelineRow(
            entry: entry,
            isFirst: index == 0,
            isLast: index == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  static const double _rowGap = AppSpacing.sm;

  final TimelineEntry entry;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                TodayFormat.clock(entry.time),
                style: AppTypography.label,
              ),
            ),
          ),
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Expanded(child: _Rail(isVisible: !isFirst)),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.isDeadline ? AppColors.coral : AppColors.white,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppBorders.width,
                    ),
                  ),
                ),
                Expanded(child: _Rail(isVisible: !isLast)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: isFirst ? 0 : _rowGap / 2,
                bottom: isLast ? AppSpacing.xxs : _rowGap / 2,
              ),
              child: _EntryPill(entry: entry),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.isVisible});

  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    return const Center(
      child: SizedBox(
        width: AppBorders.width,
        child: ColoredBox(color: AppColors.ink),
      ),
    );
  }
}

class _EntryPill extends StatelessWidget {
  const _EntryPill({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final badge = entry.badge;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: AppTheme.brutalBox(
        color: entry.color,
        borderRadius: AppRadii.inputAll,
      ),
      child: Row(
        children: [
          if (entry.color == AppColors.slate) ...[
            Icon(
              Icons.bedtime_outlined,
              size: 16,
              color: entry.foregroundColor,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Expanded(
            child: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(color: entry.foregroundColor),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.xs),
            BrutalBadge(label: badge, color: AppColors.white),
          ],
        ],
      ),
    );
  }
}
