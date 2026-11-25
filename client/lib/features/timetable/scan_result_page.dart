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
  late final List<SubjectDraft> subjects = [...widget.subjects];

  // Parallel to [subjects]: only ticked rows are saved.
  late final List<bool> picked = [for (final _ in widget.subjects) true];

  List<SubjectDraft> get pickedSubjects => [
    for (var i = 0; i < subjects.length; i++)
      if (picked[i]) subjects[i],
  ];
  bool saving = false;

  // OCR rows under this confidence get the "Kiểm tra lại" badge
  static const lowConfidence = 0.7;

  bool needsCheck(SubjectDraft s) =>
      s.confidence != null && s.confidence! < lowConfidence;

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
          'Lưu sẽ xóa các môn cũ và thay bằng ${pickedSubjects.length} môn mới.',
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

  // The OCR result as a table: tick what to keep, tap a row to fix it.
  Widget subjectTable() {
    return BrutalConfirmTable(
      headers: const ['Thứ', 'Giờ', 'Môn', 'Phòng'],
      columnFlex: const [2, 3, 4, 2],
      rows: [
        for (var i = 0; i < subjects.length; i++)
          ConfirmRow(
            cells: [
              dayName(subjects[i].dayOfWeek),
              '${subjects[i].startTime.toJson()}\n${subjects[i].endTime.toJson()}',
              subjects[i].name,
              subjects[i].room ?? '',
            ],
            selected: picked[i],
            needsCheck: needsCheck(subjects[i]),
            onSelected: saving ? null : (v) => setState(() => picked[i] = v),
            onTap: saving ? null : () => edit(i),
          ),
      ],
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
                    const Text(
                      'Bỏ tick môn đọc sai, chạm vào dòng để sửa. '
                      'Dòng đỏ là chỗ máy chưa chắc.',
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    subjectTable(),
                    const SizedBox(height: AppSpacing.md),
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
                    : 'Đúng rồi, lưu ${pickedSubjects.length} môn',
                onPressed: saving || pickedSubjects.isEmpty ? null : save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
