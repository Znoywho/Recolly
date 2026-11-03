import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const String fontFamily = 'Be Vietnam Pro';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight extraBold = FontWeight.w800;

  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 40,
    height: 1.1,
    fontWeight: extraBold,
    letterSpacing: -1,
    color: AppColors.ink,
  );
  static const TextStyle title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 1.2,
    fontWeight: extraBold,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );
  static const TextStyle subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 1.3,
    fontWeight: extraBold,
    color: AppColors.ink,
  );
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.45,
    fontWeight: regular,
    color: AppColors.ink,
  );
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.3,
    fontWeight: semiBold,
    color: AppColors.ink,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.4,
    fontWeight: regular,
    color: AppColors.inkMuted,
  );
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.2,
    fontWeight: extraBold,
    color: AppColors.ink,
  );

  static const TextTheme textTheme = TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: title,
    headlineLarge: title,
    headlineMedium: title,
    headlineSmall: subtitle,
    titleLarge: subtitle,
    titleMedium: subtitle,
    titleSmall: label,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: button,
    labelMedium: label,
    labelSmall: caption,
  );
}
