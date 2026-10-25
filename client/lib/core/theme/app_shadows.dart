import 'package:flutter/painting.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  static const Offset regularOffset = Offset(4, 4);
  static const Offset smallOffset = Offset(2, 2);

  static const BoxShadow hardRegular = BoxShadow(
    color: AppColors.ink,
    offset: regularOffset,
  );
  static const BoxShadow hardSmall = BoxShadow(
    color: AppColors.ink,
    offset: smallOffset,
  );

  static const List<BoxShadow> regular = [hardRegular];
  static const List<BoxShadow> small = [hardSmall];
  static const List<BoxShadow> none = [];

  static List<BoxShadow> hard(Offset offset) => offset == Offset.zero
      ? none
      : [BoxShadow(color: AppColors.ink, offset: offset)];
}
