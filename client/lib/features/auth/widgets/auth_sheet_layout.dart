import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class AuthSheetLayout extends StatelessWidget {
  const AuthSheetLayout({
    super.key,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.headline,
    required this.sheetChildren,
  });

  static const double sheetCornerRadius = 32;

  final Color backgroundColor;
  final Color foregroundColor;
  final String headline;
  final List<Widget> sheetChildren;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Recolly',
                        style: AppTypography.subtitle.copyWith(
                          color: foregroundColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      headline,
                      style: AppTypography.display.copyWith(
                        color: foregroundColor,
                        fontSize: 36,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: _AuthSheet(children: sheetChildren),
          ),
        ],
      ),
    );
  }
}

class _AuthSheet extends StatelessWidget {
  const _AuthSheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Transform.translate(
        offset: const Offset(0, AppBorders.width),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AuthSheetLayout.sheetCornerRadius),
            ),
            border: Border.all(color: AppColors.ink, width: AppBorders.width),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: _SheetHandle()),
                  const SizedBox(height: AppSpacing.lg),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      decoration: const BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadii.pillAll,
      ),
    );
  }
}
