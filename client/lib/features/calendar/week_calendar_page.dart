import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../todo/todo_list_page.dart';
import 'event_detail_page.dart';

// R28: week calendar (Figma "Lịch tuần" 12:1925).
// Week strip on top, timeline 6h–24h of the selected day below.
// R29: "Xếp lịch ôn" asks CP-SAT for study blocks, user picks some, then saves.
// R58: tapping a saved event opens EventDetailSheet.

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
// Why a todo could not be scheduled (UnscheduledTodo.reason)
const unscheduledReasons = {
  'NOT_ENOUGH_TIME_BEFORE_DEADLINE': 'Không đủ thời gian trước deadline',
  'MISSING_DEADLINE': 'Chưa có deadline',
  'MISSING_ESTIMATE': 'Chưa có thời lượng ước tính',
  'DEADLINE_PASSED': 'Đã quá deadline',
  'DAILY_LIMIT_REACHED': 'Đã đủ giờ học mỗi ngày',
  'ALREADY_SCHEDULED': 'Đã có lịch ôn',
};

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
    this.suggested,
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

  // Not saved yet, comes from /schedule/generate (R29)
  final ScheduleBlock? suggested;

  // Column inside the lane when blocks overlap (set by layoutColumns)
  int col = 0;
  int cols = 1;
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
  int loadId = 0;

  // R29 suggestion state
  ScheduleSuggestion? suggestion;
  Set<int> picked = {};
  Map<String, String> todoTitles = {};
  bool generating = false;
  bool applying = false;

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
    // Only the newest load may update the screen (fast week switching)
    final id = ++loadId;
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
      if (!mounted || id != loadId) return;
      setState(() {
        events = eventList;
        deadlines = todoPage.items
            .where((t) => t.deadlineAt != null && t.status != TodoStatus.done)
            .toList();
        loading = false;
      });
    } catch (e) {
      if (!mounted || id != loadId) return;
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

  // True when [start, end) shows on the selected day's 6h–24h timeline.
  // Events crossing midnight (e.g. bedtime 23:00–07:00) show on both days.
  bool onSelectedDay(DateTime start, DateTime end) {
    final from = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
      firstHour,
    );
    final to = selectedDay.add(const Duration(days: 1));
    return start.isBefore(to) && end.isAfter(from);
  }

  List<CalendarBlock> blocksOfDay() {
    final blocks = <CalendarBlock>[];
    for (final e in events) {
      if (e.allDay || !onSelectedDay(e.startAt.toLocal(), e.endAt.toLocal())) {
        continue;
      }
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
    for (final b in suggestion?.blocks ?? <ScheduleBlock>[]) {
      final start = b.startAt.toLocal();
      final end = b.endAt.toLocal();
      if (!onSelectedDay(start, end)) continue;
      final on = picked.contains(b.index);
      blocks.add(
        CalendarBlock(
          title: b.title,
          start: start,
          end: end,
          color: on ? colorOf(b.kind) : AppColors.disabled,
          textColor: on && b.kind == EventKind.bedtime
              ? AppColors.white
              : AppColors.ink,
          icon: on ? Icons.check_box : Icons.check_box_outline_blank,
          fullWidth: b.kind == EventKind.bedtime,
          suggested: b,
        ),
      );
    }
    blocks.sort((a, b) => a.start.compareTo(b.start));
    layoutColumns(blocks);
    return blocks;
  }

  // Blocks that overlap in time share the lane side by side.
  // Bedtime (full width) blocks are left out.
  void layoutColumns(List<CalendarBlock> blocks) {
    // A block is drawn at least minBlockHeight tall, so count that as its end
    final minMinutes = (minBlockHeight / hourHeight * 60).round();
    DateTime shownEnd(CalendarBlock b) {
      final minEnd = b.start.add(Duration(minutes: minMinutes));
      return b.end.isAfter(minEnd) ? b.end : minEnd;
    }

    var group = <CalendarBlock>[];
    var colEnds = <DateTime>[];
    DateTime? groupEnd;

    void closeGroup() {
      for (final b in group) {
        b.cols = colEnds.length;
      }
      group = [];
      colEnds = [];
      groupEnd = null;
    }

    for (final b in blocks.where((b) => !b.fullWidth)) {
      if (groupEnd != null && !b.start.isBefore(groupEnd!)) closeGroup();
      var col = colEnds.indexWhere((end) => !b.start.isBefore(end));
      if (col == -1) {
        col = colEnds.length;
        colEnds.add(shownEnd(b));
      } else {
        colEnds[col] = shownEnd(b);
      }
      b.col = col;
      group.add(b);
      final end = shownEnd(b);
      if (groupEnd == null || end.isAfter(groupEnd!)) groupEnd = end;
    }
    closeGroup();
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

  void showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String errorText(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError) return 'Không có mạng, thử lại sau nhé.';
      if (e.code == 'HEALTH_PROFILE_NOT_FOUND') {
        return 'Bạn cần nhập hồ sơ giấc ngủ trước khi xếp lịch.';
      }
      if (e.code == 'SUGGESTION_EXPIRED') {
        return 'Lịch đề xuất đã hết hạn, bấm nút xếp lịch lại nhé.';
      }
    }
    return 'Có lỗi xảy ra, thử lại sau nhé.';
  }

  // S1: ask the server for study blocks of the week being viewed.
  Future<void> generateSchedule() async {
    final today = dateOnly(DateTime.now());
    final weekEnd = weekStart.add(const Duration(days: 6));
    if (weekEnd.isBefore(today)) {
      showSnack('Tuần này đã qua, chọn tuần khác nhé.');
      return;
    }
    final from = weekStart.isBefore(today) ? today : weekStart;
    final repos = RepositoryScope.of(context);
    setState(() => generating = true);
    showSnack('Đang xếp lịch ôn...');
    try {
      final result = await repos.schedule.generate(
        ScheduleRequest(from: from, to: weekEnd),
      );
      // Titles for the "could not schedule" card
      final todoPage = await repos.todos.listTodos(limit: 100);
      if (!mounted) return;
      setState(() {
        suggestion = result;
        picked = {for (final b in result.blocks) b.index};
        todoTitles = {for (final t in todoPage.items) t.id: t.title};
        generating = false;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (result.blocks.isEmpty && result.unscheduled.isEmpty) {
        showSnack('Không có việc nào cần xếp lịch.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => generating = false);
      showSnack(errorText(e));
    }
  }

  // S2: save the picked blocks as events, then reload the week.
  Future<void> applySchedule() async {
    final s = suggestion;
    if (s == null || picked.isEmpty) return;
    setState(() => applying = true);
    try {
      final result = await RepositoryScope.of(context).schedule
          .apply(s.suggestionId, blockIndexes: picked.toList()..sort());
      if (!mounted) return;
      setState(() {
        suggestion = null;
        applying = false;
      });
      showSnack('Đã lưu ${result.events.length} khối vào lịch.');
      loadWeek();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        applying = false;
        if (e is ApiException && e.code == 'SUGGESTION_EXPIRED') {
          suggestion = null;
        }
      });
      showSnack(errorText(e));
    }
  }

  void cancelSuggestion() => setState(() => suggestion = null);

  void togglePick(ScheduleBlock b) {
    setState(() {
      if (!picked.remove(b.index)) picked.add(b.index);
    });
  }

  // R58: open the event detail sheet, reload when it changed.
  Future<void> openEvent(CalendarEvent e) async {
    final start = e.startAt.toLocal();
    final end = e.endAt.toLocal();
    final golden = goldenHours.any(
      (w) => w.start.toLocal().isBefore(end) && w.end.toLocal().isAfter(start),
    );
    final result = await EventDetailSheet.show(
      context,
      event: e,
      repo: RepositoryScope.of(context).events,
      golden: golden,
    );
    if (result == null || !mounted) return;
    loadWeek();
    if (result == 'deleted' && e.kind == EventKind.study) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Đã xóa khối ôn.'),
            action: SnackBarAction(
              label: 'Xếp lại',
              onPressed: generateSchedule,
            ),
          ),
        );
    } else {
      showSnack(result == 'deleted' ? 'Đã xóa.' : 'Đã dời giờ.');
    }
  }

  void showBlock(CalendarBlock block) {
    if (block.suggested != null) {
      togglePick(block.suggested!);
      return;
    }
    if (block.event != null) {
      openEvent(block.event!);
      return;
    }
    // Todo deadline: simple info sheet
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
              // Only while a suggestion is shown, so the screen stays as Figma
              if (error == null && suggestion != null) ...[
                scheduleBar(suggestion!),
                const SizedBox(height: AppSpacing.md),
              ],
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
              if (suggestion != null && suggestion!.unscheduled.isNotEmpty)
                unscheduledCard(suggestion!.unscheduled),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openTodos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TodoListPage()),
    );
    // Deadlines may have changed
    if (mounted) loadWeek();
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
          // Figma 313:33: opens the todo list
          BrutalIconButton(
            icon: Icons.checklist,
            size: 36,
            iconSize: 18,
            color: AppColors.teal,
            onPressed: openTodos,
          ),
          const SizedBox(width: AppSpacing.xs),
          // R29: not in Figma, so a small button next to the week arrows
          Tooltip(
            message: 'Xếp lịch ôn',
            child: BrutalIconButton(
              icon: Icons.auto_awesome,
              size: 36,
              iconSize: 18,
              color: AppColors.yellow,
              onPressed: generating || loading || suggestion != null
                  ? null
                  : generateSchedule,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
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

  // Offset on the selected day's timeline; times on other days are clamped.
  double topOf(DateTime t) {
    final dayStart = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
      firstHour,
    );
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
                if (blocks.isNotEmpty &&
                    sameDay(w.start.toLocal(), selectedDay))
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
                  left: hourLabelWidth + 4 + b.col * laneWidth / b.cols,
                  width: b.fullWidth
                      ? width - hourLabelWidth - 14
                      : laneWidth / b.cols - (b.cols > 1 ? 4 : 0),
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
                    message: 'Nhập thời khóa biểu hoặc thêm todo để Recolly xếp lịch ôn tập cho bạn.',
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

  // Save/cancel bar while a suggestion is shown.
  Widget scheduleBar(ScheduleSuggestion s) {
    final minutes = s.blocks
        .where((b) => picked.contains(b.index) && b.kind == EventKind.study)
        .fold<int>(
          0,
          (sum, b) => sum + b.endAt.difference(b.startAt).inMinutes,
        );
    return BrutalCard(
      color: AppColors.teal,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Đề xuất: chọn ${picked.length}/${s.blocks.length} khối',
            style: AppTypography.subtitle,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${minutes ~/ 60}h${two(minutes % 60)} ôn tập · '
            // Server ratio is for the whole suggestion, so only show it then
            '${picked.length == s.blocks.length ? '${(s.stats.goldenHourRatio * 100).round()}% trong giờ vàng. ' : ''}'
            'Chạm vào khối để bỏ chọn.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: BrutalButton(
                  label: 'Hủy',
                  color: AppColors.white,
                  onPressed: applying ? null : cancelSuggestion,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: BrutalButton(
                  label: applying ? 'Đang lưu...' : 'Lưu lịch',
                  onPressed: applying || picked.isEmpty ? null : applySchedule,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget unscheduledCard(List<UnscheduledTodo> items) {
    return BrutalCard(
      color: AppColors.coral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chưa xếp được ${items.length} việc',
            style: AppTypography.subtitle,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final u in items)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                '• ${todoTitles[u.todoId] ?? 'Một việc'}: '
                '${unscheduledReasons[u.reason] ?? u.reason}'
                '${u.missingMinutes != null ? ' (thiếu ${u.missingMinutes} phút)' : ''}',
                style: AppTypography.body,
              ),
            ),
        ],
      ),
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
      borderStyle: b.suggested != null
          ? BrutalBorderStyle.dashed
          : BrutalBorderStyle.solid,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // A short block with a large system font is clipped at the bottom
      // instead of painting the "BOTTOM OVERFLOWED" stripes.
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: blockContent(b),
        ),
      ),
    );
  }

  Widget blockContent(CalendarBlock b) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
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
          // Narrow column (overlapping events): start time only
          b.cols > 1 ? hhmm(b.start) : '${hhmm(b.start)} - ${hhmm(b.end)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.label.copyWith(color: b.textColor),
        ),
      ],
    );
  }
}
