import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../../core/di/repository_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class WeeklyStudyProgress {
  const WeeklyStudyProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get ratio => total == 0 ? 0 : completed / total;

  static Future<WeeklyStudyProgress> load(
    AppRepositories repositories, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final sessions = await repositories.events.listEvents(
      from: weekStart,
      to: weekStart.add(const Duration(days: DateTime.daysPerWeek)),
      kind: EventKind.study,
    );
    return WeeklyStudyProgress(
      completed: sessions.where((s) => s.endAt.isBefore(current)).length,
      total: sessions.length,
    );
  }
}

class MotivationDialog extends StatefulWidget {
  const MotivationDialog({super.key});

  static const String headline = 'Mỗi giờ ngủ hôm nay là điểm số ngày mai.';
  static const String trophyAsset = 'assets/trophy.png';

  static void precacheTrophy(BuildContext context) =>
      precacheImage(const AssetImage(trophyAsset), context);

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: AppColors.ink.withValues(alpha: 0.45),
    builder: (_) => const MotivationDialog(),
  );

  @override
  State<MotivationDialog> createState() => _MotivationDialogState();
}

class _MotivationDialogState extends State<MotivationDialog> {
  Future<WeeklyStudyProgress>? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progress ??= WeeklyStudyProgress.load(RepositoryScope.of(context));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: BrutalCard(
        color: AppColors.cream,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset(
              MotivationDialog.trophyAsset,
              height: 150,
              fit: BoxFit.contain,
              semanticLabel: 'Cúp thành tích',
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              MotivationDialog.headline,
              textAlign: TextAlign.center,
              style: AppTypography.title,
            ),
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<WeeklyStudyProgress>(
              future: _progress,
              builder: (context, snapshot) =>
                  _ProgressSection(snapshot: snapshot),
            ),
            const SizedBox(height: AppSpacing.lg),
            BrutalButton(
              label: 'Tiếp tục',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.snapshot});

  final AsyncSnapshot<WeeklyStudyProgress> snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }
    final progress = snapshot.data;
    if (progress == null) {
      return const Text(
        'Chưa tải được tiến độ tuần này.',
        textAlign: TextAlign.center,
        style: AppTypography.body,
      );
    }
    if (progress.total == 0) {
      return const Text(
        'Tuần này chưa có phiên ôn nào. Thêm todo để Recolly xếp lịch ôn cho bạn.',
        textAlign: TextAlign.center,
        style: AppTypography.body,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Bạn đã hoàn thành ${progress.completed}/${progress.total} '
          'phiên ôn tuần này',
          textAlign: TextAlign.center,
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.sm),
        BrutalProgressBar(value: progress.ratio, fillColor: AppColors.green),
      ],
    );
  }
}
