import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'brutal_press_feedback.dart';

class BrutalButton extends StatefulWidget {
  const BrutalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.green,
    this.icon,
    this.expanded = true,
    this.hasBorder = true,
    this.hasShadow = true,
    this.leadingIcon = false,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final bool expanded;
  final bool hasBorder;
  final bool hasShadow;
  final bool leadingIcon;
  final Widget? leading;

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> with BrutalPressFeedback {
  @override
  bool get isPressEnabled => widget.onPressed != null;

  Color get _foregroundColor =>
      isPressEnabled ? AppColors.ink : AppColors.inkMuted;

  @override
  Widget build(BuildContext context) {
    final leading = widget.leading;
    final travel = isPressed ? AppShadows.offset : Offset.zero;

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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm + AppSpacing.xxs,
            ),
            decoration: AppTheme.brutalBox(
              color: isPressEnabled ? widget.color : AppColors.disabled,
              borderRadius: AppRadii.pillAll,
              hasShadow: isPressEnabled && !isPressed && widget.hasShadow,
              hasBorder: widget.hasBorder,
            ),
            child: Row(
              mainAxisSize: widget.expanded
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: AppSpacing.sm),
                ] else if (widget.icon != null && widget.leadingIcon) ...[
                  Icon(widget.icon, size: 18, color: _foregroundColor),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.button.copyWith(
                      color: _foregroundColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
