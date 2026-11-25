import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.name, this.subtitle});

  final String name;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return BrutalCard(
      color: AppColors.teal,
      child: Row(
        children: [
          const BrutalIconTile(
            icon: Icons.person_outline_rounded,
            color: AppColors.yellow,
            size: 64,
            iconSize: 34,
            hasShadow: false,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
