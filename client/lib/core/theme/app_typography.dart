import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const TextStyle display = TextStyle(
    fontSize: 40,
    height: 1.05,
    fontWeight: FontWeight.w900,
    letterSpacing: -1,
    color: AppColors.ink,
  );
  static const TextStyle headline = TextStyle(
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );
  static const TextStyle title = TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
    color: AppColors.ink,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: AppColors.inkMuted,
  );
  static const TextStyle button = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );

  static const TextTheme textTheme = TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: headline,
    headlineLarge: headline,
    headlineMedium: headline,
    headlineSmall: title,
    titleLarge: title,
    titleMedium: title,
    titleSmall: label,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: button,
    labelMedium: label,
    labelSmall: caption,
  );
}
