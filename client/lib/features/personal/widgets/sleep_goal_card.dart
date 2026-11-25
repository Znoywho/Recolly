import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class SleepGoalCard extends StatelessWidget {
  const SleepGoalCard({
    super.key,
    required this.hours,
    required this.onChanged,
    required this.onChangeEnd,
  });

  static const double minHours = 6;
  static const double maxHours = 9;
  static const double stepHours = 0.5;

  final double hours;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  static String hoursLabel(double hours) =>
      '${hours == hours.roundToDouble() ? hours.toInt() : hours} giờ';

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Mục tiêu giấc ngủ', style: AppTypography.body),
              ),
              BrutalBadge(label: hoursLabel(hours)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.ink,
              inactiveTrackColor: AppColors.ink,
              disabledActiveTrackColor: AppColors.inkMuted,
              disabledInactiveTrackColor: AppColors.inkMuted,
              thumbColor: AppColors.green,
              disabledThumbColor: AppColors.disabled,
              overlayColor: AppColors.green.withValues(alpha: 0.3),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 12,
                elevation: 0,
                pressedElevation: 0,
              ),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: hours.clamp(minHours, maxHours),
              min: minHours,
              max: maxHours,
              divisions: ((maxHours - minHours) / stepHours).round(),
              semanticFormatterCallback: hoursLabel,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(hoursLabel(minHours), style: AppTypography.label),
              Text(hoursLabel(maxHours), style: AppTypography.label),
            ],
          ),
        ],
      ),
    );
  }
}
