import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/theme/app_theme.dart';

enum BrutalBorderStyle { solid, dashed }

class BrutalCard extends StatelessWidget {
  const BrutalCard({
    super.key,
    required this.child,
    this.color = AppColors.white,
    this.borderStyle = BrutalBorderStyle.solid,
    this.hasShadow = true,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final Color color;
  final BrutalBorderStyle borderStyle;
  final bool hasShadow;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDashed = borderStyle == BrutalBorderStyle.dashed;
    final card = Container(
      padding: padding,
      decoration: AppTheme.brutalBox(
        color: color,
        hasBorder: !isDashed,
        hasShadow: hasShadow,
      ),
      child: child,
    );
    if (!isDashed) return card;
    return CustomPaint(
      foregroundPainter: const _DashedBorderPainter(
        color: AppColors.ink,
        strokeWidth: AppBorders.width,
        radius: AppRadii.card,
      ),
      child: card,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  static const double _dashLength = 8;
  static const double _gapLength = 6;

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius - inset),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final dashEnd = math.min(distance + _dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, dashEnd), paint);
        distance = dashEnd + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      radius != oldDelegate.radius;
}
