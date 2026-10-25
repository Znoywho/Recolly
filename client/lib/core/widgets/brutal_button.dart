import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum BrutalButtonVariant { primary, secondary, ghost, danger }

class BrutalButton extends StatefulWidget {
  const BrutalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BrutalButtonVariant.primary,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrutalButtonVariant variant;
  final IconData? icon;
  final bool expanded;

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> {
  static const Duration _pressDuration = Duration(milliseconds: 70);

  bool _isPressed = false;

  bool get _isEnabled => widget.onPressed != null;

  bool get _hasShadow =>
      _isEnabled && widget.variant != BrutalButtonVariant.ghost;

  Color get _backgroundColor {
    if (!_isEnabled) return AppColors.disabled;
    return switch (widget.variant) {
      BrutalButtonVariant.primary => AppColors.lime,
      BrutalButtonVariant.secondary => AppColors.paper,
      BrutalButtonVariant.ghost => Colors.transparent,
      BrutalButtonVariant.danger => AppColors.coral,
    };
  }

  Color get _foregroundColor => _isEnabled ? AppColors.ink : AppColors.inkMuted;

  void _setPressed(bool isPressed) {
    if (!_isEnabled || _isPressed == isPressed) return;
    setState(() => _isPressed = isPressed);
  }

  @override
  Widget build(BuildContext context) {
    final restingOffset = _hasShadow ? AppShadows.regularOffset : Offset.zero;
    final shadowOffset = _isPressed ? Offset.zero : restingOffset;
    final travel = restingOffset - shadowOffset;

    return Semantics(
      button: true,
      enabled: _isEnabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedContainer(
          duration: _pressDuration,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(travel.dx, travel.dy, 0),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + AppSpacing.xxs,
          ),
          decoration: BrutalDecoration.box(
            color: _backgroundColor,
            borderRadius: AppRadii.pillAll,
            shadowOffset: shadowOffset,
          ),
          child: Row(
            mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: _foregroundColor),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.button.copyWith(color: _foregroundColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
