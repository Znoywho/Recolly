import 'package:flutter/painting.dart';

import 'app_colors.dart';

abstract final class AppBorders {
  static const double regularWidth = 2;
  static const double thickWidth = 3;

  static const BorderSide regular = BorderSide(
    color: AppColors.ink,
    width: regularWidth,
  );
  static const BorderSide thick = BorderSide(
    color: AppColors.ink,
    width: thickWidth,
  );
}
