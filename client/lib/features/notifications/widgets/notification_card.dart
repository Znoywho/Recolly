import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../../today/today_format.dart';
import '../notifications_data.dart';

class NotificationCard extends StatelessWidget {
  const NotificationCard({super.key, required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final category = notification.category;
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrutalIconTile(
                icon: category.icon,
                color: category.color,
                size: 44,
                iconSize: 24,
                shape: BrutalButtonShape.square,
                hasShadow: false,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: AppTypography.body.copyWith(
                        fontWeight: AppTypography.semiBold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      TodayFormat.clock(notification.time),
                      style: AppTypography.label,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(notification.message, style: AppTypography.body),
        ],
      ),
    );
  }
}
