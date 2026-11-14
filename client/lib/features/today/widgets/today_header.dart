import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class TodayHeader extends StatelessWidget {
  const TodayHeader({
    super.key,
    required this.greeting,
    required this.name,
    this.onProfilePressed,
  });

  final String greeting;
  final String name;
  final VoidCallback? onProfilePressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '$greeting,\n$name',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.title,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        BrutalIconButton(
          icon: Icons.person_outline_rounded,
          iconSize: 26,
          color: AppColors.yellow,
          onPressed: onProfilePressed ?? () {},
        ),
      ],
    );
  }
}
