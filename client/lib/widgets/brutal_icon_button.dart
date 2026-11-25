import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'brutal_press_feedback.dart';

enum BrutalButtonShape { circle, square }

class BrutalIconButton extends StatefulWidget {
  const BrutalIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = AppColors.white,
    this.iconColor,
    this.size = 48.0,
    this.iconSize = 20.0,
    this.hasBorder = true,
    this.hasShadow = true,
    this.shape = BrutalButtonShape.circle,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final bool hasBorder;
  final bool hasShadow;
  final BrutalButtonShape shape;

  @override
  State<BrutalIconButton> createState() => _BrutalIconButtonState();
}

class _BrutalIconButtonState extends State<BrutalIconButton>
    with BrutalPressFeedback {
  @override
  bool get isPressEnabled => widget.onPressed != null;

  Color get _foregroundColor =>
      widget.iconColor ?? (isPressEnabled ? AppColors.ink : AppColors.inkMuted);

  @override
  Widget build(BuildContext context) {
    final travel = isPressed ? AppShadows.offset : Offset.zero;
    final borderRadius = widget.shape == BrutalButtonShape.circle
        ? BorderRadius.circular(widget.size / 2)
        : AppRadii.cardAll;

    return Semantics(
      button: true,
      enabled: isPressEnabled,
      child: pressListener(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: BrutalPressFeedback.pressAnimationDuration,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(travel.dx, travel.dy, 0),
            width: widget.size,
            height: widget.size,
            decoration: AppTheme.brutalBox(
              color: isPressEnabled ? widget.color : AppColors.disabled,
              borderRadius: borderRadius,
              hasShadow: isPressEnabled && !isPressed && widget.hasShadow,
              hasBorder: widget.hasBorder,
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _foregroundColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
