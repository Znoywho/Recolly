import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class PersonalPage extends StatelessWidget {
  const PersonalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          Text('Cá nhân', style: AppTypography.title),
          SizedBox(height: AppSpacing.md),
          BrutalCard(
            borderStyle: BrutalBorderStyle.dashed,
            hasShadow: false,
            child: Text(
              'Hồ sơ, cài đặt nhắc nhở và tài khoản Google sẽ hiển thị ở đây.',
              style: AppTypography.body,
            ),
          ),
        ],
      ),
    );
  }
}
