import 'dart:math' as math;

import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../today_format.dart';

class SleepDebtCard extends StatelessWidget {
  const SleepDebtCard({
    super.key,
    required this.totalDebtMinutes,
    this.nights = const [],
  });

  final int totalDebtMinutes;
  final List<SleepDebtDay> nights;

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      color: AppColors.yellow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nợ giấc ngủ', style: AppTypography.label),
                const SizedBox(height: AppSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    TodayFormat.sleepDebt(totalDebtMinutes),
                    style: AppTypography.title.copyWith(fontSize: 30),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                const Text('San hô: thiếu ngủ', style: AppTypography.caption),
              ],
            ),
          ),
          if (nights.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            _NightBars(nights: nights),
          ],
        ],
      ),
    );
  }
}

class _NightBars extends StatelessWidget {
  const _NightBars({required this.nights});

  static const double _maxBarHeight = 48;
  static const double _minBarHeight = 10;

  final List<SleepDebtDay> nights;

  @override
  Widget build(BuildContext context) {
    final longestSleep = nights.map((n) => n.sleptMinutes).fold(1, math.max);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final night in nights)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: math.max(
                    _minBarHeight,
                    _maxBarHeight * night.sleptMinutes / longestSleep,
                  ),
                  decoration: AppTheme.brutalBox(
                    color: _barColor(night),
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    hasShadow: false,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  TodayFormat.weekdayLabel(night.date),
                  style: AppTypography.label.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Color _barColor(SleepDebtDay night) {
    if (!night.hasData) return AppColors.disabled;
    return night.sleptMinutes < night.needMinutes
        ? AppColors.coral
        : AppColors.white;
  }
}
