import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class SleepTipCard extends StatelessWidget {
  const SleepTipCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      color: AppColors.yellow,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: AppTypography.body)),
        ],
      ),
    );
  }
}
