import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../../today/today_format.dart';

class SleepDebtHeroCard extends StatelessWidget {
  const SleepDebtHeroCard({super.key, required this.totalDebtMinutes});

  final int totalDebtMinutes;

  @override
  Widget build(BuildContext context) {
    final hasDebt = totalDebtMinutes > 0;
    return BrutalCard(
      color: AppColors.teal,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nợ giấc ngủ tuần này', style: AppTypography.label),
                const SizedBox(height: AppSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hasDebt
                        ? TodayFormat.duration(totalDebtMinutes)
                        : 'Đủ giấc',
                    style: AppTypography.display.copyWith(
                      color: hasDebt ? AppColors.danger : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _MoonBadge(),
        ],
      ),
    );
  }
}

class _MoonBadge extends StatelessWidget {
  const _MoonBadge();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: SizedBox(
        width: 96,
        height: 84,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: 0,
              child: Icon(
                Icons.nightlight_round,
                size: 76,
                color: AppColors.yellow,
                shadows: [Shadow(color: AppColors.ink, offset: Offset(4, 4))],
              ),
            ),
            Positioned(right: 0, top: 0, child: Icon(Icons.add, size: 30)),
          ],
        ),
      ),
    );
  }
}
