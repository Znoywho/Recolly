import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';

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
    this.predictedKss,
    this.isAsleep = false,
  });

  final int score;
  final double? predictedKss;
  final bool isAsleep;
}

class AlertnessScoreCard extends StatelessWidget {
  const AlertnessScoreCard({super.key, required this.snapshot, this.onRetry});

  final AlertnessSnapshot snapshot;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      color: AppColors.lagoon,
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
            variant: BrutalButtonVariant.secondary,
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
    final predictedKss = snapshot.predictedKss;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${snapshot.score}%', style: AppTypography.display),
        const SizedBox(height: AppSpacing.sm),
        BrutalProgressBar(
          value: snapshot.score / 100,
          fillColor: AppColors.sunflower,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (predictedKss != null)
              BrutalBadge(
                label: 'KSS ${predictedKss.toStringAsFixed(1)}',
                color: AppColors.paper,
              ),
            if (snapshot.isAsleep)
              const BrutalBadge(
                label: 'Đang ngủ',
                icon: Icons.bedtime_rounded,
                color: AppColors.slate,
                foregroundColor: AppColors.onSlate,
              ),
          ],
        ),
      ],
    );
  }
}
