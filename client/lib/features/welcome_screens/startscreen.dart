import 'package:client/features/calendar/add_schedule_screen.dart';
import 'package:client/features/theme_gallery/navigation_preview_page.dart';
import 'package:client/widgets/brutal_button.dart';
import 'package:client/widgets/brutal_card.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/brutal_progress_bar.dart';

class Startscreen extends StatelessWidget {
  const Startscreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrutalButton(
                label: "Bắt đầu",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddScheduleScreen(),
                    ),
                  );
                },
                color: AppColors.green,
              ),
              const SizedBox(height: AppSpacing.xs),
              BrutalButton(
                label: "Bỏ qua",
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NavigationPreviewPage(),
                    ),
                    (route) => false,
                  );
                },
                color: AppColors.cream,
                hasShadow: false,
                hasBorder: false,
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: const [
              Row(
                children: [
                  Expanded(
                    child: BrutalProgressBar(
                      value: 0.3,
                      fillColor: AppColors.green,
                      trackColor: AppColors.white,
                    ),
                  ),
                  SizedBox(width: AppSpacing.xs),
                  Text('1/3',
                    style: AppTypography.label,),
                ],
              ),
              SizedBox(height: AppSpacing.md),
              Flexible(
                child: BrutalCard(
                  color: AppColors.teal,
                  child: Image(
                    image: AssetImage('assets/phones.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                "Chụp thời khóa biểu, lịch tự động có ngay",
                style: AppTypography.title,
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                "Chỉ cần một tấm ảnh, Recolly đọc và sắp xếp lịch học cho bạn.",
                style: AppTypography.body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
