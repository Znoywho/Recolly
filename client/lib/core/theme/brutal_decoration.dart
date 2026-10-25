import 'package:flutter/painting.dart';

import 'app_borders.dart';
import 'app_colors.dart';
import 'app_radii.dart';
import 'app_shadows.dart';

abstract final class BrutalDecoration {
  static BoxDecoration box({
    Color color = AppColors.paper,
    BorderRadius borderRadius = AppRadii.mdAll,
    Offset shadowOffset = AppShadows.regularOffset,
    double borderWidth = AppBorders.regularWidth,
  }) => BoxDecoration(
    color: color,
    borderRadius: borderRadius,
    border: Border.all(color: AppColors.ink, width: borderWidth),
    boxShadow: AppShadows.hard(shadowOffset),
  );
}
