import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

// R28: week calendar (Figma "Lịch tuần" 12:1925).
// Week strip on top, timeline 6h–24h of the selected day below.

const int firstHour = 6;
const int lastHour = 24;
const double hourHeight = 27;
const double hourLabelWidth = 40;
const double goldenLaneWidth = 85;
const double minBlockHeight = 46;
const Color skeletonColor = Color(0xFFE4DFD2);

// Placeholder blocks while loading (start hour, end hour, full width)
const skeletonSlots = [
  (7.0, 9.0, false),
  (9.5, 11.0, false),
  (12.0, 14.0, false),
  (15.0, 17.0, false),
  (18.0, 20.0, false),
  (20.0, 22.0, false),
  (22.0, 24.0, true),
];

const weekdayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
const weekdayLongNames = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];

// One block on the timeline (event or todo deadline).
class CalendarBlock {
  CalendarBlock({
    required this.title,
    required this.start,
    required this.end,
    required this.color,
    this.textColor = AppColors.ink,
    this.icon,
    this.fullWidth = false,
    this.event,
    this.todo,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final bool fullWidth;
  final CalendarEvent? event;
  final Todo? todo;
}

class WeekCalendarPage extends StatefulWidget {
  const WeekCalendarPage({super.key, this.onImportTimetable});

  // Empty state button, goes to "Nhập thời khóa biểu" (R13)
  final VoidCallback? onImportTimetable;

  @override
  State<WeekCalendarPage> createState() => _WeekCalendarPageState();
}

class _WeekCalendarPageState extends State<WeekCalendarPage> {
  late DateTime selectedDay = dateOnly(DateTime.now());
  List<CalendarEvent> events = [];
  List<Todo> deadlines = [];
  List<BiorhythmWindow> goldenHours = [];
  bool loading = true;
  bool started = false;
  String? error;

  DateTime get weekStart =>
      selectedDay.subtract(Duration(days: selectedDay.weekday - 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      loadWeek();
    }
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> loadWeek() async {
    final repos = RepositoryScope.of(context);
    final from = weekStart;
    final to = from.add(const Duration(days: 7));
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final eventList = await repos.events.listEvents(from: from, to: to);
      final todoPage = await repos.todos.listTodos(
        query: TodoQuery(dueAfter: from, dueBefore: to),
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        events = eventList;
        deadlines = todoPage.items
            .where((t) => t.deadlineAt != null && t.status != TodoStatus.done)
            .toList();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            'Không tải được dữ liệu. Kiểm tra Wi-Fi hoặc 4G rồi thử lại nhé.';
      });
    }
    loadGoldenHours();
  }

  // Golden hours come from Process S/C (biorhythm API).
  Future<void> loadGoldenHours() async {
    final day = selectedDay;
    try {
      final bio = await RepositoryScope.of(context).sleep
          .getBiorhythm(date: day, days: 1);
      if (!mounted || day != selectedDay) return;
      setState(() => goldenHours = bio.peakWindows);
    } catch (e) {
      if (!mounted) return;
      setState(() => goldenHours = []);
    }
  }

  void changeWeek(int step) {
    selectedDay = selectedDay.add(Duration(days: 7 * step));
    loadWeek();
  }

  void selectDay(DateTime day) {
    setState(() {
      selectedDay = day;
      goldenHours = [];
    });
    loadGoldenHours();
  }

  List<CalendarBlock> blocksOfDay() {
    final blocks = <CalendarBlock>[];
    for (final e in events) {
      if (e.allDay || !sameDay(e.startAt.toLocal(), selectedDay)) continue;
      blocks.add(
        CalendarBlock(
          title: e.title,
          start: e.startAt.toLocal(),
          end: e.endAt.toLocal(),
          color: colorOf(e.kind),
          textColor: e.kind == EventKind.bedtime
              ? AppColors.white
              : AppColors.ink,
          icon: e.kind == EventKind.bedtime ? Icons.nightlight_round : null,
          fullWidth: e.kind == EventKind.bedtime,
          event: e,
        ),
      );
    }
    for (final t in deadlines) {
      final due = t.deadlineAt!.toLocal();
      if (!sameDay(due, selectedDay)) continue;
      blocks.add(
        CalendarBlock(
          title: 'Hạn: ${t.title}',
          start: due.subtract(const Duration(hours: 1)),
          end: due,
          color: AppColors.coral,
          todo: t,
        ),
      );
    }
    blocks.sort((a, b) => a.start.compareTo(b.start));
    return blocks;
  }

  static Color colorOf(EventKind kind) => switch (kind) {
    EventKind.classSession => AppColors.white,
    EventKind.study => AppColors.green,
    EventKind.rest => AppColors.teal,
    EventKind.bedtime => AppColors.slate,
    EventKind.other => AppColors.yellow,
  };

  static String two(int n) => n.toString().padLeft(2, '0');

  static String hhmm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  static String shortHour(DateTime d) =>
      d.minute == 0 ? '${d.hour}h' : '${d.hour}h${two(d.minute)}';

  String weekLabel() {
    final end = weekStart.add(const Duration(days: 6));
    if (weekStart.month == end.month) {
      return 'Tuần ${weekStart.day} – ${end.day} tháng ${end.month}, ${end.year}';
    }
    return 'Tuần ${weekStart.day}/${weekStart.month} – ${end.day}/${end.month}, ${end.year}';
  }

  void showBlock(CalendarBlock block) {
    // Simple info sheet; full event detail screen is R58.
    final e = block.event;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cream,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(block.title, style: AppTypography.subtitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${hhmm(block.start)} - ${hhmm(block.end)}',
              style: AppTypography.label,
            ),
            if (e?.location != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Phòng: ${e!.location}', style: AppTypography.body),
            ],
            if (e?.description != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(e!.description!, style: AppTypography.body),
            ],
            if (block.todo != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Deadline lúc ${hhmm(block.end)}',
                style: AppTypography.body,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = blocksOfDay();
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadWeek,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.whitespace,
            ),
            children: [
              header(),
              const SizedBox(height: AppSpacing.xxs),
              Text(weekLabel(), style: AppTypography.label),
              const SizedBox(height: AppSpacing.sm),
              weekStrip(),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${weekdayLongNames[selectedDay.weekday - 1]}, '
                    '${selectedDay.day} tháng ${selectedDay.month}',
                    style: AppTypography.label,
                  ),
                  if (!loading && error == null)
                    Text(
                      '${blocks.length} sự kiện',
                      style: AppTypography.label.copyWith(
                        fontWeight: AppTypography.regular,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (error != null)
                statusCard(
                  color: AppColors.coral,
                  icon: Icons.wifi_off_rounded,
                  title: 'Mất kết nối',
                  message: error!,
                  button: 'Thử lại',
                  onPressed: loadWeek,
                )
              else
                timeline(loading ? [] : blocks),
            ],
          ),
        ),
      ),
    );
  }

  Widget header() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Tháng ${selectedDay.month}',
              style: AppTypography.title,
            ),
          ),
          BrutalIconButton(
            icon: Icons.chevron_left,
            size: 36,
            iconSize: 18,
            onPressed: () => changeWeek(-1),
          ),
          const SizedBox(width: AppSpacing.xs),
          BrutalIconButton(
            icon: Icons.chevron_right,
            size: 36,
            iconSize: 18,
            onPressed: () => changeWeek(1),
          ),
        ],
      ),
    );
  }

  Widget weekStrip() {
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(child: dayPill(weekStart.add(Duration(days: i)), i)),
        ],
      ],
    );
  }

  Widget dayPill(DateTime day, int index) {
    final selected = sameDay(day, selectedDay);
    return GestureDetector(
      onTap: () => selectDay(day),
      child: Container(
        height: 60,
        decoration: AppTheme.brutalBox(
          color: selected ? AppColors.green : AppColors.white,
          borderRadius: AppRadii.pillAll,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(weekdayNames[index], style: AppTypography.label),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${day.day}',
              style: AppTypography.body.copyWith(
                fontWeight: selected
                    ? AppTypography.extraBold
                    : AppTypography.regular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double topOf(DateTime t) {
    final dayStart = DateTime(t.year, t.month, t.day, firstHour);
    final hours = t.difference(dayStart).inMinutes / 60;
    return hours.clamp(0, (lastHour - firstHour).toDouble()) * hourHeight;
  }

  Widget timeline(List<CalendarBlock> blocks) {
    const height = (lastHour - firstHour) * hourHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final laneWidth = width - hourLabelWidth - 4 - goldenLaneWidth - 8;
        return SizedBox(
          height: height + AppSpacing.md,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Hour lines + labels
              for (var h = firstHour; h <= lastHour; h++)
                Positioned(
                  top: (h - firstHour) * hourHeight,
                  left: 0,
                  right: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: hourLabelWidth,
                        child: Transform.translate(
                          offset: const Offset(0, -8),
                          child: Text('${h}h', style: AppTypography.label),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: AppColors.ink.withValues(alpha: 0.19),
                        ),
                      ),
                    ],
                  ),
                ),
              // Vertical time axis
              Positioned(
                top: 0,
                left: hourLabelWidth,
                child: Container(
                  width: 1,
                  height: height,
                  color: AppColors.ink.withValues(alpha: 0.19),
                ),
              ),
              if (loading) ...[
                for (final slot in skeletonSlots)
                  Positioned(
                    top: (slot.$1 - firstHour) * hourHeight,
                    left: hourLabelWidth + 4,
                    width: slot.$3 ? width - hourLabelWidth - 14 : laneWidth,
                    height: (slot.$2 - slot.$1) * hourHeight - 4,
                    child: skeleton(),
                  ),
                Positioned(
                  top: (9 - firstHour) * hourHeight,
                  right: 0,
                  width: goldenLaneWidth,
                  height: 2.5 * hourHeight,
                  child: skeleton(),
                ),
              ],
              // Golden hours lane (right side), hidden when the day is empty
              for (final w in goldenHours)
                if (blocks.isNotEmpty && sameDay(w.start.toLocal(), selectedDay))
                  Positioned(
                    top: topOf(w.start.toLocal()),
                    right: 0,
                    width: goldenLaneWidth,
                    height: blockHeight(w.start.toLocal(), w.end.toLocal()),
                    child: BrutalCard(
                      color: AppColors.yellow,
                      borderStyle: BrutalBorderStyle.dashed,
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Giờ vàng', style: AppTypography.label),
                            Text(
                              '${shortHour(w.start.toLocal())}–'
                              '${shortHour(w.end.toLocal())}',
                              style: AppTypography.label,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              // Events and deadlines
              for (final b in blocks)
                Positioned(
                  top: topOf(b.start),
                  left: hourLabelWidth + 4,
                  width: b.fullWidth ? width - hourLabelWidth - 14 : laneWidth,
                  height: blockHeight(b.start, b.end),
                  child: GestureDetector(
                    onTap: () => showBlock(b),
                    child: eventBlock(b),
                  ),
                ),
              if (!loading && blocks.isEmpty)
                Positioned(
                  top: 60,
                  left: 36,
                  right: 12,
                  child: statusCard(
                    color: AppColors.yellow,
                    icon: Icons.edit_calendar_outlined,
                    title: 'Chưa có lịch hôm nay',
                    message:
                        'Nhập thời khóa biểu hoặc thêm todo để Recolly xếp lịch ôn tập cho bạn.',
                    button: 'Nhập thời khóa biểu',
                    onPressed: widget.onImportTimetable,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget skeleton() {
    return Container(
      decoration: BoxDecoration(
        color: skeletonColor,
        borderRadius: AppRadii.cardAll,
      ),
    );
  }

  // Shared look for empty / error states (Figma "Thẻ trạng thái")
  Widget statusCard({
    required Color color,
    required IconData icon,
    required String title,
    required String message,
    required String button,
    required VoidCallback? onPressed,
  }) {
    return BrutalCard(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: AppTheme.brutalBox(
              color: color,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(icon, size: 28, color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.subtitle.copyWith(fontSize: 20),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(height: 1.3),
          ),
          const SizedBox(height: AppSpacing.md),
          BrutalButton(label: button, onPressed: onPressed),
        ],
      ),
    );
  }

  double blockHeight(DateTime start, DateTime end) {
    final h = topOf(end) - topOf(start) - 4;
    return h < minBlockHeight ? minBlockHeight : h;
  }

  Widget eventBlock(CalendarBlock b) {
    return BrutalCard(
      color: b.color,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (b.icon != null) ...[
                Icon(b.icon, size: 18, color: b.textColor),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  b.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    color: b.textColor,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          Text(
            '${hhmm(b.start)} - ${hhmm(b.end)}',
            style: AppTypography.label.copyWith(color: b.textColor),
          ),
        ],
      ),
    );
  }
}
