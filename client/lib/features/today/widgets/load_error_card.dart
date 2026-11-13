import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class LoadErrorCard extends StatelessWidget {
  const LoadErrorCard({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (error) {
      ApiException(isNetworkError: true) => (
        Icons.wifi_off_rounded,
        'Mất kết nối',
        'Không tải được dữ liệu. Kiểm tra Wi-Fi hoặc 4G rồi thử lại nhé.',
      ),
      ApiException(isNotFound: true) => (
        Icons.bedtime_outlined,
        'Chưa có hồ sơ giấc ngủ',
        'Hoàn tất hồ sơ giấc ngủ để Recolly tính nhịp sinh học cho bạn.',
      ),
      _ => (
        Icons.error_outline_rounded,
        'Có lỗi xảy ra',
        'Không tải được dữ liệu hôm nay. Thử lại sau nhé.',
      ),
    };

    return BrutalCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: AppTheme.brutalBox(
              color: AppColors.coral,
              borderRadius: AppRadii.pillAll,
            ),
            child: Icon(icon, size: 30),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.subtitle,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(message, textAlign: TextAlign.center, style: AppTypography.body),
          const SizedBox(height: AppSpacing.lg),
          BrutalButton(label: 'Thử lại', onPressed: onRetry),
        ],
      ),
    );
  }
}
