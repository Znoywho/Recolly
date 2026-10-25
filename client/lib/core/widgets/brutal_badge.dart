import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

class BrutalBadge extends StatelessWidget {
  const BrutalBadge({
    super.key,
    required this.label,
    this.color = AppColors.sunflower,
    this.foregroundColor = AppColors.ink,
    this.icon,
  });

  final String label;
  final Color color;
  final Color foregroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs + 2,
      ),
      decoration: BrutalDecoration.box(
        color: color,
        borderRadius: AppRadii.pillAll,
        shadowOffset: AppShadows.smallOffset,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            label,
            style: AppTypography.label.copyWith(color: foregroundColor),
          ),
        ],
      ),
    );
  }
}
