import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class SleepEmptyCard extends StatelessWidget {
  const SleepEmptyCard({super.key, required this.onLogSleep});

  final VoidCallback onLogSleep;

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          const BrutalIconTile(icon: Icons.bedtime_outlined),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Chưa có dữ liệu giấc ngủ',
            textAlign: TextAlign.center,
            style: AppTypography.subtitle,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Ghi giờ ngủ và giờ thức vài ngày để Recolly tính nợ ngủ và giờ vàng cho bạn.',
            textAlign: TextAlign.center,
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          BrutalButton(label: 'Ghi giấc ngủ đêm qua', onPressed: onLogSleep),
        ],
      ),
    );
  }
}
