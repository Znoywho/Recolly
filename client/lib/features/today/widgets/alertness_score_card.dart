import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../today_format.dart';

AlertnessSnapshot alertnessSnapshotOf(HomeOverview overview) {
  final score = overview.now.alertnessScore;
  if (score == null) return const AlertnessUnavailable();
  final peak = overview.nextPeakWindow;
  return AlertnessReady(
    score: score,
    goldenWindowLabel: peak == null
        ? null
        : TodayFormat.window(peak.start, peak.end),
    isAsleep: overview.now.asleep,
  );
}

sealed class AlertnessSnapshot {
  const AlertnessSnapshot();
}

final class AlertnessLoading extends AlertnessSnapshot {
  const AlertnessLoading();
}

final class AlertnessFailed extends AlertnessSnapshot {
  const AlertnessFailed(this.message);

  final String message;
}

final class AlertnessUnavailable extends AlertnessSnapshot {
  const AlertnessUnavailable();
}

final class AlertnessReady extends AlertnessSnapshot {
  const AlertnessReady({
    required this.score,
    this.goldenWindowLabel,
    this.isAsleep = false,
  });

  final int score;
  final String? goldenWindowLabel;
  final bool isAsleep;
}

class AlertnessScoreCard extends StatelessWidget {
  const AlertnessScoreCard({
    super.key,
    required this.snapshot,
    this.onRetry,
    this.onTap,
  });

  final AlertnessSnapshot snapshot;
  final VoidCallback? onRetry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = _buildCard();
    final onTap = this.onTap;
    if (onTap == null) return card;
    return Semantics(
      button: true,
      hint: 'Xem nhịp sinh học hôm nay',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }

  Widget _buildCard() {
    return BrutalCard(
      color: AppColors.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mức tỉnh táo hiện tại', style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          switch (snapshot) {
            AlertnessLoading() => const _LoadingContent(),
            AlertnessFailed(:final message) => _FailedContent(
              message: message,
              onRetry: onRetry,
            ),
            AlertnessUnavailable() => const _UnavailableContent(),
            final AlertnessReady ready => _ReadyContent(snapshot: ready),
          },
        ],
      ),
    );
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        SizedBox(width: AppSpacing.sm),
        Text('Đang tải dữ liệu…', style: AppTypography.body),
      ],
    );
  }
}

class _FailedContent extends StatelessWidget {
  const _FailedContent({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(message, style: AppTypography.body)),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          BrutalButton(
            label: 'Thử lại',
            icon: Icons.refresh_rounded,
            color: AppColors.white,
            expanded: false,
            onPressed: onRetry,
          ),
        ],
      ],
    );
  }
}

class _UnavailableContent extends StatelessWidget {
  const _UnavailableContent();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Chưa có điểm tỉnh táo. Hoàn tất hồ sơ giấc ngủ để Recolly tính nhịp sinh học của bạn.',
      style: AppTypography.body,
    );
  }
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent({required this.snapshot});

  final AlertnessReady snapshot;

  @override
  Widget build(BuildContext context) {
    final goldenWindowLabel = snapshot.goldenWindowLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${snapshot.score}%', style: AppTypography.display),
            ),
            Icon(
              snapshot.isAsleep
                  ? Icons.bedtime_outlined
                  : Icons.wb_sunny_outlined,
              size: 30,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        BrutalProgressBar(value: snapshot.score / 100),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (goldenWindowLabel != null)
              BrutalBadge(label: 'Giờ vàng: $goldenWindowLabel'),
            if (snapshot.isAsleep)
              const BrutalBadge(
                label: 'Đang ngủ',
                icon: Icons.bedtime_rounded,
                color: AppColors.slate,
                foregroundColor: AppColors.white,
              ),
          ],
        ),
      ],
    );
  }
}
