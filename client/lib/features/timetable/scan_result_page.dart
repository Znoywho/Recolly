import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'edit_subject_sheet.dart';

// R14: "Kiểm tra lại lịch học". The user checks the OCR result (or adds
// subjects by hand), then saves the timetable. Pops `true` when saved.
class ScanResultPage extends StatefulWidget {
  const ScanResultPage({super.key, required this.subjects});

  final List<SubjectDraft> subjects;

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage> {
  late final List<SubjectDraft> subjects = [
    for (final s in widget.subjects) stretchOneDay(s),
  ];

  // A photo of one week gives start == end; true when we guessed the semester.
  late bool guessedSemester = widget.subjects.any(isOneDay);

  // Parallel to [subjects]: only ticked rows are saved.
  late final List<bool> picked = [for (final _ in widget.subjects) true];

  List<SubjectDraft> get pickedSubjects => [
    for (var i = 0; i < subjects.length; i++)
      if (picked[i]) subjects[i],
  ];
  bool saving = false;

  // Subjects (not sessions) with at least one ticked session.
  int get pickedCount =>
      groups.values.where((ix) => ix.any((i) => picked[i])).length;

  // OCR rows under this confidence get the "Kiểm tra lại" badge
  static const lowConfidence = 0.7;

  bool needsCheck(SubjectDraft s) =>
      s.confidence != null && s.confidence! < lowConfidence;

  // Earliest start and latest end over all sessions.
  DateTime get semesterStart =>
      subjects.map((s) => s.startDate).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get semesterEnd =>
      subjects.map((s) => s.endDate).reduce((a, b) => a.isAfter(b) ? a : b);

  // Session indexes grouped by subject (name + code), in first-seen order.
  Map<String, List<int>> get groups {
    final result = <String, List<int>>{};
    for (var i = 0; i < subjects.length; i++) {
      final key = '${subjects[i].name}|${subjects[i].code ?? ''}';
      result.putIfAbsent(key, () => []).add(i);
    }
    return result;
  }

  // Picks a new semester range and applies it to every session.
  Future<void> pickSemester() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: semesterStart, end: semesterEnd),
      helpText: 'Học kỳ từ ngày nào đến ngày nào?',
    );
    if (range == null) return;
    setState(() {
      guessedSemester = false;
      for (var i = 0; i < subjects.length; i++) {
        subjects[i] = withDates(subjects[i], range.start, range.end);
      }
    });
  }

  Future<void> edit(int index) async {
    final result = await showEditSubjectSheet(context, subjects[index]);
    if (result is SubjectDraft) {
      setState(() => subjects[index] = result);
    } else if (result == EditSubjectSheet.delete) {
      setState(() {
        subjects.removeAt(index);
        picked.removeAt(index);
      });
    }
  }

  Future<void> add() async {
    // Reuse the semester dates of the other subjects if there are any
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = subjects.isNotEmpty ? subjects.first : null;
    final empty = SubjectDraft(
      name: '',
      dayOfWeek: 1,
      startTime: const ClockTime(7, 30),
      endTime: const ClockTime(9, 30),
      startDate: first?.startDate ?? today,
      endDate: first?.endDate ?? today.add(const Duration(days: 7 * 15)),
    );
    final result = await showEditSubjectSheet(context, empty, isNew: true);
    if (result is SubjectDraft) {
      setState(() {
        subjects.add(result);
        picked.add(true);
      });
    }
  }

  Future<void> save() async {
    final repo = RepositoryScope.of(context).timetable;
    setState(() => saving = true);
    try {
      // Saving replaces the old timetable, so ask first if there is one
      final old = await repo.listSubjects();
      if (old.isNotEmpty) {
        final ok = await confirmReplace(old.length);
        if (ok != true) {
          setState(() => saving = false);
          return;
        }
      }
      await repo.saveSubjects(pickedSubjects, replaceExisting: true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lưu được, thử lại nhé')),
      );
    }
  }

  Future<bool?> confirmReplace(int oldCount) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thay thời khóa biểu cũ?'),
        content: Text(
          'Bạn đang có $oldCount môn trong thời khóa biểu. '
          'Lưu sẽ xóa các môn cũ và thay bằng $pickedCount môn mới.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Thay thế'),
          ),
        ],
      ),
    );
  }

  // Tappable bar with the semester range shared by all subjects.
  Widget semesterBar() {
    return GestureDetector(
      onTap: saving ? null : pickSemester,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: AppTheme.brutalBox(color: AppColors.yellow),
        child: Row(
          children: [
            const Icon(Icons.date_range),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Học kỳ: ${dateText(semesterStart)} → ${dateText(semesterEnd)}',
                    style: AppTypography.label.copyWith(
                      fontWeight: AppTypography.extraBold,
                    ),
                  ),
                  if (guessedSemester)
                    const Text(
                      'Ảnh chỉ có 1 tuần nên mình đoán 15 tuần. Chạm để sửa.',
                      style: AppTypography.body,
                    ),
                ],
              ),
            ),
            const Icon(Icons.edit),
          ],
        ),
      ),
    );
  }

  // One card per subject: tick to keep, tap a session chip to fix it.
  Widget subjectCard(List<int> indexes) {
    final first = subjects[indexes.first];
    final allPicked = indexes.every((i) => picked[i]);
    final nonePicked = indexes.every((i) => !picked[i]);
    final unsure = indexes.any((i) => needsCheck(subjects[i]));
    final details = [
      ?first.code,
      if (first.room != null) shortRoom(first.room!),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: AppTheme.brutalBox(
        color: nonePicked ? AppColors.cream : AppColors.white,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            tristate: true,
            value: allPicked ? true : (nonePicked ? false : null),
            onChanged: saving
                ? null
                : (_) => setState(() {
                    for (final i in indexes) {
                      picked[i] = !allPicked;
                    }
                  }),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(first.name, style: AppTypography.subtitle),
                if (details.isNotEmpty)
                  Text(details, style: AppTypography.body),
                if (unsure) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  const BrutalBadge(
                    label: 'Kiểm tra lại',
                    color: AppColors.coral,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [for (final i in indexes) sessionChip(i)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // "T5 06:45–09:15"; tapping opens the existing edit sheet for this session.
  Widget sessionChip(int i) {
    final s = subjects[i];
    return GestureDetector(
      onTap: saving ? null : () => edit(i),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: AppTheme.brutalBox(
          color: needsCheck(s) ? AppColors.coral : AppColors.teal,
          borderRadius: AppRadii.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${shortDayName(s.dayOfWeek)} '
              '${s.startTime.toJson()}–${s.endTime.toJson()}',
              style: AppTypography.label,
            ),
            const SizedBox(width: AppSpacing.xxs),
            const Icon(Icons.edit, size: 14),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Row(
                    children: [
                      BrutalIconButton(
                        icon: Icons.arrow_back,
                        size: 40,
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          'Recolly',
                          textAlign: TextAlign.center,
                          style: AppTypography.subtitle.copyWith(fontSize: 20),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: AppTheme.brutalBox(
                          color: AppColors.yellow,
                          borderRadius: AppRadii.pillAll,
                        ),
                        child: const Text('2 / 2', style: AppTypography.label),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Kiểm tra lại lịch học',
                    style: AppTypography.title,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (subjects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Chưa có môn nào. Bấm "Thêm môn" để nhập tay nhé.',
                        style: AppTypography.body,
                      ),
                    ),
                  if (subjects.isNotEmpty) ...[
                    semesterBar(),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Bỏ tick môn đọc sai, chạm vào buổi học để sửa.',
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final indexes in groups.values) subjectCard(indexes),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  BrutalButton(
                    label: 'Thêm môn',
                    icon: Icons.add,
                    leadingIcon: true,
                    color: AppColors.white,
                    onPressed: saving ? null : add,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: BrutalButton(
                label: saving
                    ? 'Đang lưu...'
                    : 'Đúng rồi, lưu $pickedCount môn',
                onPressed: saving || pickedSubjects.isEmpty ? null : save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// T2 ... T7, CN (1 = Monday).
String shortDayName(int day) => day == 7 ? 'CN' : 'T${day + 1}';

// "E204 - CS1 (P.Thạnh Mỹ Tây, TP.HCM)" -> "E204": the campus part is noise.
String shortRoom(String room) => room.split(' - ').first.trim();

// True when a session starts and ends on the same day (one-week photo).
bool isOneDay(SubjectDraft s) => !s.endDate.isAfter(s.startDate);

// A one-day session becomes a 15-week semester, like a hand-added subject.
SubjectDraft stretchOneDay(SubjectDraft s) => isOneDay(s)
    ? withDates(s, s.startDate, s.startDate.add(const Duration(days: 7 * 15)))
    : s;

// Same session with a new date range.
SubjectDraft withDates(SubjectDraft s, DateTime start, DateTime end) =>
    SubjectDraft(
      name: s.name,
      code: s.code,
      room: s.room,
      lecturer: s.lecturer,
      dayOfWeek: s.dayOfWeek,
      startTime: s.startTime,
      endTime: s.endTime,
      startDate: start,
      endDate: end,
      color: s.color,
      confidence: s.confidence,
    );
