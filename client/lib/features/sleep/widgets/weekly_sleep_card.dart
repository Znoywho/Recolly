import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../../today/today_format.dart';
import '../../today/widgets/barchat.dart';

class WeeklySleepCard extends StatelessWidget {
  const WeeklySleepCard({
    super.key,
    required this.nights,
    required this.goalMinutes,
  });

  final List<SleepDebtDay> nights;
  final int goalMinutes;

  @override
  Widget build(BuildContext context) {
    final sortedNights = [...nights]..sort((a, b) => a.date.compareTo(b.date));
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Giấc ngủ ${sortedNights.length} ngày',
                  style: AppTypography.subtitle,
                ),
              ),
              Text(
                'Mục tiêu: ${TodayFormat.duration(goalMinutes)}',
                style: AppTypography.label,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 150,
            child: WeeklySleepBarChart(
              goalHours: goalMinutes / Duration.minutesPerHour,
              nights: [
                for (final night in sortedNights)
                  NightSleepBar(
                    label: TodayFormat.weekdayLabel(night.date),
                    sleptHours: night.sleptMinutes / Duration.minutesPerHour,
                    isEnough: night.sleptMinutes >= night.needMinutes,
                    hasData: night.hasData,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _LegendItem(label: 'Ngủ đủ', color: AppColors.green),
              _LegendItem(label: 'Thiếu ngủ', color: AppColors.coral),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: AppTheme.brutalBox(
            color: color,
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            hasShadow: false,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.label),
      ],
    );
  }
}
