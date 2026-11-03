import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

// Shape
enum BrutalButtonShape { circle, square }

class BrutalIconButton extends StatefulWidget {
  const BrutalIconButton({
    super.key,
    required this.icon, // Changes icon
    required this.onPressed,
    this.color = AppColors.white,
    this.iconColor,
    this.size = 48.0, // Defaut size
    this.iconSize = 20.0,
    this.hasBorder = true,
    this.hasShadow = true,
    this.shape = BrutalButtonShape.circle, //Defaute is circle shape
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

class _BrutalIconButtonState extends State<BrutalIconButton> {
  static const Duration _pressDuration = Duration(milliseconds: 70);

  bool _isPressed = false;

  bool get _isEnabled => widget.onPressed != null;

  Color get _foregroundColor =>
      widget.iconColor ?? (_isEnabled ? AppColors.ink : AppColors.inkMuted);

  void _setPressed(bool isPressed) {
    if (!_isEnabled || _isPressed == isPressed) return;
    setState(() => _isPressed = isPressed);
  }

  @override
  Widget build(BuildContext context) {
    final showShadow = _isEnabled && !_isPressed && widget.hasShadow;
    final travel = _isPressed ? AppShadows.offset : Offset.zero;

    // Radius
    final borderRadius = widget.shape == BrutalButtonShape.circle
        ? BorderRadius.circular(widget.size / 2)
        : AppRadii.cardAll;

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
          width: widget.size,
          height: widget.size,
          decoration: AppTheme.brutalBox(
            color: _isEnabled ? widget.color : AppColors.disabled,
            borderRadius: borderRadius,
            hasShadow: showShadow,
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
    );
  }
}