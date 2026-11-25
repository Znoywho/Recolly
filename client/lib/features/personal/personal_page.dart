import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../sync/google_calendar_sheet.dart';

class PersonalPage extends StatelessWidget {
  const PersonalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const Text('Cá nhân', style: AppTypography.title),
          const SizedBox(height: AppSpacing.lg),
          BrutalButton(
            label: 'Google Calendar',
            icon: Icons.event_available_outlined,
            leadingIcon: true,
            color: AppColors.white,
            onPressed: () => GoogleCalendarSheet.show(context),
          ),
          const SizedBox(height: AppSpacing.md),
          const BrutalCard(
            borderStyle: BrutalBorderStyle.dashed,
            hasShadow: false,
            child: Text(
              'Hồ sơ, cài đặt nhắc nhở và tài khoản sẽ hiển thị ở đây.',
              style: AppTypography.body,
            ),
          ),
        ],
      ),
    );
  }
}
