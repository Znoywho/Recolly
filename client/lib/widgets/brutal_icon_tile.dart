import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'brutal_icon_button.dart';

class BrutalIconTile extends StatelessWidget {
  const BrutalIconTile({
    super.key,
    required this.icon,
    this.color = AppColors.teal,
    this.size = 56,
    this.iconSize = 28,
    this.shape = BrutalButtonShape.circle,
    this.hasShadow = true,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final BrutalButtonShape shape;
  final bool hasShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: AppTheme.brutalBox(
        color: color,
        borderRadius: shape == BrutalButtonShape.circle
            ? AppRadii.pillAll
            : AppRadii.inputAll,
        hasShadow: hasShadow,
      ),
      child: Icon(icon, size: iconSize, color: AppColors.ink),
    );
  }
}
