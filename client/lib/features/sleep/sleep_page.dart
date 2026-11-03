import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class SleepPage extends StatelessWidget {
  const SleepPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          Text('Giấc ngủ', style: AppTypography.title),
          SizedBox(height: AppSpacing.md),
          BrutalCard(
            borderStyle: BrutalBorderStyle.dashed,
            hasShadow: false,
            child: Text(
              'Nhật ký giấc ngủ và biểu đồ nợ ngủ sẽ hiển thị ở đây.',
              style: AppTypography.body,
            ),
          ),
        ],
      ),
    );
  }
}
