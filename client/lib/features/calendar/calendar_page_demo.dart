import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          Text('Lịch', style: AppTypography.title),
          SizedBox(height: AppSpacing.md),
          BrutalCard(
            borderStyle: BrutalBorderStyle.dashed,
            hasShadow: true,
            child: Text(
              'Lịch tuần và lịch học gợi ý sẽ hiển thị ở đây test.',
              style: AppTypography.body,
            ),
          ),
        ],
      ),
    );
  }
}
