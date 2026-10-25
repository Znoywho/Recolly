import 'package:flutter/material.dart';

import 'app_borders.dart';
import 'app_colors.dart';
import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.lime,
    onPrimary: AppColors.ink,
    secondary: AppColors.lagoon,
    onSecondary: AppColors.ink,
    tertiary: AppColors.sunflower,
    onTertiary: AppColors.ink,
    error: AppColors.coral,
    onError: AppColors.ink,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.ink,
    outlineVariant: AppColors.ink,
    surfaceTint: Colors.transparent,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.paper,
    shadow: AppColors.ink,
  );

  static const RoundedRectangleBorder _pillShape = RoundedRectangleBorder(
    borderRadius: AppRadii.pillAll,
    side: AppBorders.regular,
  );

  static const EdgeInsets _buttonPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.sm,
  );

  static ButtonStyle _buttonStyle(Color background) => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? AppColors.disabled
          : background,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? AppColors.inkMuted
          : AppColors.ink,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    textStyle: const WidgetStatePropertyAll(AppTypography.button),
    padding: const WidgetStatePropertyAll(_buttonPadding),
    shape: const WidgetStatePropertyAll(_pillShape),
    side: const WidgetStatePropertyAll(AppBorders.regular),
  );

  static OutlineInputBorder _inputBorder(BorderSide side) =>
      OutlineInputBorder(borderRadius: AppRadii.mdAll, borderSide: side);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: AppTypography.textTheme,
    primaryTextTheme: AppTypography.textTheme,
    iconTheme: const IconThemeData(color: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.headline,
      shape: Border(bottom: AppBorders.regular),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.mdAll,
        side: AppBorders.regular,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _buttonStyle(AppColors.lime),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _buttonStyle(AppColors.lime),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonStyle(AppColors.paper),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(
          AppTypography.button.copyWith(decoration: TextDecoration.underline),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.paper,
      labelStyle: AppTypography.label,
      floatingLabelStyle: AppTypography.label,
      hintStyle: AppTypography.caption,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      border: _inputBorder(AppBorders.regular),
      enabledBorder: _inputBorder(AppBorders.regular),
      focusedBorder: _inputBorder(AppBorders.thick),
      errorBorder: _inputBorder(
        AppBorders.regular.copyWith(color: AppColors.coral),
      ),
      focusedErrorBorder: _inputBorder(
        AppBorders.thick.copyWith(color: AppColors.coral),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.paper,
      selectedColor: AppColors.sunflower,
      disabledColor: AppColors.disabled,
      labelStyle: AppTypography.label,
      side: AppBorders.regular,
      shape: StadiumBorder(side: AppBorders.regular),
      showCheckmark: false,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.ink,
      thickness: AppBorders.regularWidth,
      space: AppSpacing.lg,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
      linearTrackColor: AppColors.paper,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(AppColors.paper),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.lime
            : AppColors.disabled,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(AppColors.ink),
      trackOutlineWidth: const WidgetStatePropertyAll(AppBorders.regularWidth),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.paper,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
    ),
  );
}
