import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../welcome_screens/startscreen.dart';

class AddScheduleScreen extends StatelessWidget {
  const AddScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      bottomNavigationBar: BrutalBottomNavBar(
        currentTab: BrutalNavTab.calendar,
        onTabSelected: (tab) {},
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Row(
              children: [
                BrutalIconButton(
                  icon: Icons.arrow_back,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Startscreen()),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: AppSpacing.md),
            Text("Thêm thời khóa biểu", style: AppTypography.title),
            SizedBox(height: AppSpacing.xxl),
            BrutalCard(
              borderStyle: BrutalBorderStyle.dashed,
              hasShadow: true,
              child: Column(
                children: [
                  SizedBox(height: AppSpacing.sm),
                  BrutalIconButton(
                    icon: Icons.camera_alt_outlined,
                    onPressed: () {},
                    shape: BrutalButtonShape.square,
                    color: AppColors.teal,
                  ),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'Chụp thời khóa biểu của bạn',
                    style: AppTypography.body,
                  ),
                  SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            BrutalButton(
              label: "Chụp ảnh",
              onPressed: () {},
              icon: Icons.camera_alt_outlined,
              leadingIcon: true,
            ),
          ],
        ),
      ),
    );
  }
}
