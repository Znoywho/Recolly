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
  bool saving = false;

  // Figma 2:1374: teal / yellow in turn, flagged cards are white
  static const cardColors = [AppColors.teal, AppColors.yellow];

  // OCR rows under this confidence get the "Kiểm tra lại" badge
  static const lowConfidence = 0.7;

  bool needsCheck(SubjectDraft s) =>
      s.confidence != null && s.confidence! < lowConfidence;

  Future<void> edit(int index) async {
    final result = await showEditSubjectSheet(context, subjects[index]);
    if (result is SubjectDraft) {
      setState(() => subjects[index] = result);
    } else if (result == EditSubjectSheet.delete) {
      setState(() => subjects.removeAt(index));
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
      setState(() => subjects.add(result));
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
      await repo.saveSubjects(subjects, replaceExisting: true);
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
          'Lưu sẽ xóa các môn cũ và thay bằng ${subjects.length} môn mới.',
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

  Widget subjectCard(int index) {
    final s = subjects[index];
    final check = needsCheck(s);
    final room = s.room;
    // Color index counts only the cards that are not flagged
    final colorIndex = subjects.take(index).where((x) => !needsCheck(x)).length;
    const text = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 15,
      height: 1.3,
      color: AppColors.ink,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GestureDetector(
        onTap: saving ? null : () => edit(index),
        child: BrutalCard(
          color: check
              ? AppColors.white
              : cardColors[colorIndex % cardColors.length],
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      style: text.copyWith(fontWeight: AppTypography.semiBold),
                    ),
                  ),
                  // Figma shows the pencil only on cards to check
                  if (check) const Icon(Icons.edit_outlined, size: 20),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              if (room != null && room.isNotEmpty) ...[
                Text('· $room', style: text),
                const SizedBox(height: AppSpacing.xxs),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '· ${dayName(s.dayOfWeek)} · '
                      '${s.startTime.toJson()}-${s.endTime.toJson()}',
                      style: text,
                    ),
                  ),
                  if (check)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      decoration: AppTheme.brutalBox(color: AppColors.coral),
                      child: const Text(
                        'Kiểm tra lại',
                        style: AppTypography.label,
                      ),
                    ),
                ],
              ),
            ],
          ),
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
                  for (var i = 0; i < subjects.length; i++) subjectCard(i),
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
                label: saving ? 'Đang lưu...' : 'Lưu thời khóa biểu',
                onPressed: saving || subjects.isEmpty ? null : save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
