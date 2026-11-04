import 'package:client/core/theme/app_theme.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';

import 'auth_controller.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.yellow,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: BrutalButton(
            label: controller.busy ? 'Đang đăng nhập...' : 'Đăng nhập với Google',
            icon: Icons.login,
            leadingIcon: true,
            onPressed: controller.busy ? null : controller.signIn,
            color: AppColors.green,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Text('Recolly', style: AppTypography.display),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Đăng nhập để Recolly xếp lịch học theo nhịp sinh học của bạn.',
                style: AppTypography.body,
              ),
              const Spacer(),
              const BrutalCard(
                child: Text(
                  'Recolly sẽ xin quyền Google Calendar để đẩy lịch học của bạn lên lịch Google.',
                  style: AppTypography.caption,
                ),
              ),
              if (controller.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  controller.error!,
                  style: AppTypography.label.copyWith(color: AppColors.coral),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
