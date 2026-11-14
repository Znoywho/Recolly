import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class NightSleepBar {
  const NightSleepBar({
    required this.label,
    required this.sleptHours,
    required this.isEnough,
    this.hasData = true,
  });

  final String label;
  final double sleptHours;
  final bool isEnough;
  final bool hasData;
}

class WeeklySleepBarChart extends StatelessWidget {
  const WeeklySleepBarChart({
    super.key,
    required this.nights,
    required this.goalHours,
  });

  static const double _missingBarHours = 1;
  static const double _headroomHours = 0.5;

  final List<NightSleepBar> nights;
  final double goalHours;

  double get _maxY =>
      [
        goalHours,
        for (final night in nights) night.sleptHours,
      ].reduce((a, b) => a > b ? a : b) +
      _headroomHours;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: _maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(enabled: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: _dayTitle,
            ),
          ),
        ),
        barGroups: [
          for (final (index, night) in nights.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: night.hasData ? night.sleptHours : _missingBarHours,
                  width: 24,
                  color: _colorOf(night),
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                  borderSide: const BorderSide(
                    color: AppColors.ink,
                    width: AppBorders.width,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayTitle(double value, TitleMeta meta) {
    final index = value.toInt();
    if (index < 0 || index >= nights.length) return const SizedBox.shrink();
    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: Text(nights[index].label, style: AppTypography.label),
    );
  }

  static Color _colorOf(NightSleepBar night) {
    if (!night.hasData) return AppColors.disabled;
    return night.isEnough ? AppColors.green : AppColors.coral;
  }
}

class EnergyWindow {
  const EnergyWindow({required this.startHour, required this.endHour});

  final double startHour;
  final double endHour;
}

class DailyEnergyChart extends StatelessWidget {
  const DailyEnergyChart({
    super.key,
    required this.sleepPressure,
    required this.wakeRhythm,
    this.goodWindows = const [],
    this.drowsyWindows = const [],
  });

  static const double firstHour = 6;
  static const double lastHour = 24;
  static const double _hourStep = 3;

  final List<FlSpot> sleepPressure;
  final List<FlSpot> wakeRhythm;
  final List<EnergyWindow> goodWindows;
  final List<EnergyWindow> drowsyWindows;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: firstHour,
        maxX: lastHour,
        minY: 0,
        maxY: 1,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: [
            for (final window in goodWindows) _band(window, AppColors.green),
            for (final window in drowsyWindows) _band(window, AppColors.coral),
          ],
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 0.5,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.disabled, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: AppColors.ink, width: AppBorders.width),
            bottom: BorderSide(color: AppColors.ink, width: AppBorders.width),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: _hourStep,
              reservedSize: 26,
              getTitlesWidget: _hourTitle,
            ),
          ),
        ),
        lineBarsData: [
          _line(sleepPressure),
          _line(wakeRhythm, dashArray: const [6, 5]),
        ],
      ),
    );
  }

  static VerticalRangeAnnotation _band(EnergyWindow window, Color color) =>
      VerticalRangeAnnotation(
        x1: window.startHour.clamp(firstHour, lastHour),
        x2: window.endHour.clamp(firstHour, lastHour),
        color: color,
      );

  static LineChartBarData _line(List<FlSpot> spots, {List<int>? dashArray}) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        preventCurveOverShooting: true,
        color: AppColors.ink,
        barWidth: 3,
        isStrokeCapRound: true,
        dashArray: dashArray,
        dotData: const FlDotData(show: false),
      );

  static Widget _hourTitle(double value, TitleMeta meta) {
    if (value % _hourStep != 0) return const SizedBox.shrink();
    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: Text(
        '${value.toInt()}h',
        style: AppTypography.label.copyWith(fontSize: 11),
      ),
    );
  }
}

class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({super.key});

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: _getBottomTitles,
              reservedSize: 28,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: _createSampleData(),
      ),
    );
  }

  List<BarChartGroupData> _createSampleData() {
    final values = [6.0, 9.0, 5.5, 8.5, 4.5, 9.5, 6.5];

    return List.generate(values.length, (i) {
      final bool isHighlighted = i == 1 || i == 3 || i == 5;

      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: values[i],
            color: isHighlighted ? Colors.white : const Color(0xFFE88B73),
            width: 14,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
              bottom: Radius.circular(6),
            ),
            borderSide: isHighlighted
                ? const BorderSide(color: Color(0xFFE88B73), width: 2)
                : BorderSide.none,
            backDrawRodData: BackgroundBarChartRodData(show: false),
          ),
        ],
      );
    });
  }

  Widget _getBottomTitles(double value, TitleMeta meta) {
    const style = TextStyle(
      color: Colors.black87,
      fontWeight: FontWeight.bold,
      fontSize: 11,
    );

    String text = switch (value.toInt()) {
      0 => 'T2',
      1 => 'T3',
      2 => 'T4',
      3 => 'T5',
      4 => 'T6',
      5 => 'T7',
      6 => 'CN',
      _ => '',
    };

    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: Text(text, style: style),
    );
  }
}
