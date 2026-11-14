import 'package:client/data/data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import 'barchat.dart';

class EnergyChartCard extends StatelessWidget {
  const EnergyChartCard({super.key, required this.biorhythm});

  final Biorhythm biorhythm;

  double _hourOf(DateTime time) =>
      time.difference(biorhythm.date).inMinutes / Duration.minutesPerHour;

  bool _isVisible(double hour) =>
      hour >= DailyEnergyChart.firstHour && hour <= DailyEnergyChart.lastHour;

  List<EnergyWindow> _windows(List<BiorhythmWindow> windows) => [
    for (final window in windows)
      if (_hourOf(window.end) > DailyEnergyChart.firstHour &&
          _hourOf(window.start) < DailyEnergyChart.lastHour)
        EnergyWindow(
          startHour: _hourOf(window.start),
          endHour: _hourOf(window.end),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final visiblePoints = [
      for (final point in biorhythm.points)
        if (_isVisible(_hourOf(point.time))) point,
    ];
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Năng lượng trong ngày', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          const _LineLegend(label: 'Áp lực ngủ', isDashed: false),
          const SizedBox(height: AppSpacing.xxs),
          const _LineLegend(label: 'Nhịp thức tỉnh', isDashed: true),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 180,
            child: DailyEnergyChart(
              sleepPressure: [
                for (final point in visiblePoints)
                  FlSpot(_hourOf(point.time), point.processS.clamp(0, 1)),
              ],
              wakeRhythm: [
                for (final point in visiblePoints)
                  FlSpot(
                    _hourOf(point.time),
                    ((point.processC + 1) / 2).clamp(0, 1),
                  ),
              ],
              goodWindows: _windows(biorhythm.peakWindows),
              drowsyWindows: _windows(biorhythm.lowWindows),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _SwatchLegend(label: 'Học tốt', color: AppColors.green),
              _SwatchLegend(label: 'Dễ buồn ngủ', color: AppColors.coral),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineLegend extends StatelessWidget {
  const _LineLegend({required this.label, required this.isDashed});

  final String label;
  final bool isDashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: isDashed
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_Dash(), _Dash(), _Dash()],
                )
              : const SizedBox(
                  height: AppBorders.width + 0.5,
                  child: ColoredBox(color: AppColors.ink),
                ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.label),
      ],
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 6,
      height: AppBorders.width + 0.5,
      child: ColoredBox(color: AppColors.ink),
    );
  }
}

class _SwatchLegend extends StatelessWidget {
  const _SwatchLegend({required this.label, required this.color});

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
