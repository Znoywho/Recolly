import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../../today/today_format.dart';

class BedtimeCard extends StatelessWidget {
  const BedtimeCard({
    super.key,
    required this.recommendedSleepAt,
    required this.isReminderOn,
    required this.isSaving,
    required this.onReminderPressed,
  });

  final DateTime recommendedSleepAt;
  final bool isReminderOn;
  final bool isSaving;
  final VoidCallback onReminderPressed;

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Giờ đi ngủ gợi ý: ${TodayFormat.clock(recommendedSleepAt)}',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          BrutalButton(
            label: isReminderOn ? 'Đã bật nhắc nhở' : 'Đặt nhắc nhở',
            icon: isReminderOn
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_rounded,
            leadingIcon: true,
            color: isReminderOn ? AppColors.white : AppColors.green,
            onPressed: isSaving ? null : onReminderPressed,
          ),
        ],
      ),
    );
  }
}
