import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'widgets/live_alertness_card.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          Text('Hôm nay', style: AppTypography.title),
          SizedBox(height: AppSpacing.md),
          LiveAlertnessCard(),
          SizedBox(height: AppSpacing.md),
          BrutalCard(
            borderStyle: BrutalBorderStyle.dashed,
            hasShadow: false,
            child: Text(
              'Lịch hôm nay và việc cần làm sẽ hiển thị ở đây.',
              style: AppTypography.body,
            ),
          ),
        ],
      ),
    );
  }
}
