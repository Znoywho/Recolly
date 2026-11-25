import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../../today/today_format.dart';
import '../notifications_data.dart';

class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.notification,
    this.chronotype,
  });

  final AppNotification notification;

  /// The user's animal reminds them; falls back to the category icon.
  final Chronotype? chronotype;

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
              if (chronotype case final chronotype?)
                AnimalMascot(animal: MascotAnimal.of(chronotype), size: 52)
              else
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
