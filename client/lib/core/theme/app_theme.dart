import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_typography.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double whitespace = 100;
}

abstract final class AppRadii {
  static const double card = 16;
  static const double input = 12;
  static const double pill = 999;

  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius inputAll = BorderRadius.all(Radius.circular(input));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

abstract final class AppBorders {
  static const double width = 2.5;

  static const BorderSide side = BorderSide(color: AppColors.ink, width: width);
}

abstract final class AppShadows {
  static const Offset offset = Offset(0, 4);

  static const List<BoxShadow> hard = [
    BoxShadow(color: AppColors.ink, offset: offset),
  ];
  static const List<BoxShadow> none = [];
}

abstract final class AppTheme {
  static BoxDecoration brutalBox({
    Color color = AppColors.white,
    BorderRadius borderRadius = AppRadii.cardAll,
    bool hasBorder = true,
    bool hasShadow = true,
  }) => BoxDecoration(
    color: color,
    borderRadius: borderRadius,
    border: hasBorder ? Border.fromBorderSide(AppBorders.side) : null,
    boxShadow: hasShadow ? AppShadows.hard : AppShadows.none,
  );

  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.green,
    onPrimary: AppColors.ink,
    secondary: AppColors.teal,
    onSecondary: AppColors.ink,
    tertiary: AppColors.yellow,
    onTertiary: AppColors.ink,
    error: AppColors.coral,
    onError: AppColors.ink,
    surface: AppColors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.ink,
    outlineVariant: AppColors.ink,
    surfaceTint: Colors.transparent,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.white,
    shadow: AppColors.ink,
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
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: AppRadii.pillAll,
        side: AppBorders.side,
      ),
    ),
    side: const WidgetStatePropertyAll(AppBorders.side),
  );

  static OutlineInputBorder _inputBorder(BorderSide side) =>
      OutlineInputBorder(borderRadius: AppRadii.inputAll, borderSide: side);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    fontFamily: AppTypography.fontFamily,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.cream,
    canvasColor: AppColors.cream,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: AppTypography.textTheme,
    primaryTextTheme: AppTypography.textTheme,
    iconTheme: const IconThemeData(color: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.title,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardAll,
        side: AppBorders.side,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _buttonStyle(AppColors.green),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _buttonStyle(AppColors.green),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonStyle(AppColors.white),
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
      fillColor: AppColors.white,
      labelStyle: AppTypography.label,
      floatingLabelStyle: AppTypography.label,
      hintStyle: AppTypography.caption,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      border: _inputBorder(AppBorders.side),
      enabledBorder: _inputBorder(AppBorders.side),
      focusedBorder: _inputBorder(AppBorders.side),
      errorBorder: _inputBorder(
        AppBorders.side.copyWith(color: AppColors.coral),
      ),
      focusedErrorBorder: _inputBorder(
        AppBorders.side.copyWith(color: AppColors.coral),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.white,
      selectedColor: AppColors.yellow,
      disabledColor: AppColors.disabled,
      labelStyle: AppTypography.label,
      side: AppBorders.side,
      shape: StadiumBorder(side: AppBorders.side),
      showCheckmark: false,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.white,
      elevation: 0,
      titleTextStyle: AppTypography.subtitle,
      contentTextStyle: AppTypography.body,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardAll,
        side: AppBorders.side,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.ink,
      thickness: AppBorders.width,
      space: AppSpacing.lg,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
      linearTrackColor: AppColors.white,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(AppColors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.green
            : AppColors.disabled,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(AppColors.ink),
      trackOutlineWidth: const WidgetStatePropertyAll(AppBorders.width),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 14,
        fontWeight: AppTypography.semiBold,
        color: AppColors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.inputAll),
    ),
  );
}
