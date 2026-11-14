import 'package:flutter/widgets.dart';

import '../core/theme/app_theme.dart';

class BrutalProgressBar extends StatelessWidget {
  const BrutalProgressBar({
    super.key,
    required this.value,
    this.fillColor = AppColors.ink,
    this.trackColor = AppColors.white,
    this.height = 16,
  });

  final double value;
  final Color fillColor;
  final Color trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: AppTheme.brutalBox(
        color: trackColor,
        borderRadius: AppRadii.pillAll,
        hasShadow: false,
      ),
      child: ClipRRect(
        borderRadius: AppRadii.pillAll,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            heightFactor: 1,
            child: ColoredBox(color: fillColor),
          ),
        ),
      ),
    );
  }
}
