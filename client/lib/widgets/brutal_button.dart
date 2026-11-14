import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

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
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final bool expanded;
  final bool hasBorder;
  final bool hasShadow;
  final bool leadingIcon;

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> {
  static const Duration _pressDuration = Duration(milliseconds: 70);

  bool _isPressed = false;

  bool get _isEnabled => widget.onPressed != null;

  Color get _foregroundColor => _isEnabled ? AppColors.ink : AppColors.inkMuted;

  void _setPressed(bool isPressed) {
    if (!_isEnabled || _isPressed == isPressed) return;
    setState(() => _isPressed = isPressed);
  }

  @override
  Widget build(BuildContext context) {
    final hasShadow = _isEnabled && !_isPressed;
    final travel = _isPressed ? AppShadows.offset : Offset.zero;

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
          decoration: AppTheme.brutalBox(
            color: _isEnabled ? widget.color : AppColors.disabled,
            borderRadius: AppRadii.pillAll,
            hasShadow: _isEnabled && !_isPressed && widget.hasShadow,
            hasBorder: widget.hasBorder,
          ),
          child: Row(
            mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Kiểm tra thêm điều kiện widget.leadingIcon phải là true thì mới hiển thị icon
              if (widget.icon != null && widget.leadingIcon) ...[
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