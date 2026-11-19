import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class InsetTextField extends StatefulWidget {
  const InsetTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.isPassword = false,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  static const double cornerRadius = 14;
  static const Offset insetShadowOffset = Offset(3, 3);

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool isPassword;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<InsetTextField> createState() => _InsetTextFieldState();
}

class _InsetTextFieldState extends State<InsetTextField> {
  late bool _isTextHidden = widget.isPassword;

  void _toggleTextVisibility() =>
      setState(() => _isTextHidden = !_isTextHidden);

  @override
  Widget build(BuildContext context) {
    final errorText = widget.errorText;
    final helperText = errorText ?? widget.helperText;
    final outlineColor = errorText == null ? AppColors.ink : AppColors.danger;
    const radius = BorderRadius.all(
      Radius.circular(InsetTextField.cornerRadius),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: radius,
            border: Border.all(color: outlineColor, width: AppBorders.width),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(
              Radius.circular(InsetTextField.cornerRadius - AppBorders.width),
            ),
            child: Stack(
              children: [
                TextField(
                  controller: widget.controller,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  autofillHints: widget.autofillHints,
                  obscureText: _isTextHidden,
                  enableSuggestions: !widget.isPassword,
                  autocorrect: !widget.isPassword,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: AppTypography.body,
                  cursorColor: AppColors.ink,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: AppTypography.body.copyWith(
                      color: AppColors.inkMuted,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md - 2,
                    ),
                    suffixIcon: widget.isPassword
                        ? IconButton(
                            onPressed: _toggleTextVisibility,
                            tooltip: _isTextHidden
                                ? 'Hiện mật khẩu'
                                : 'Ẩn mật khẩu',
                            icon: Icon(
                              _isTextHidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.ink,
                            ),
                          )
                        : null,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _InsetShadowPainter(
                        color: outlineColor,
                        offset: InsetTextField.insetShadowOffset,
                        radius: InsetTextField.cornerRadius - AppBorders.width,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            helperText,
            style: AppTypography.caption.copyWith(
              color: errorText == null ? AppColors.inkMuted : AppColors.danger,
            ),
          ),
        ],
      ],
    );
  }
}

class _InsetShadowPainter extends CustomPainter {
  const _InsetShadowPainter({
    required this.color,
    required this.offset,
    required this.radius,
  });

  final Color color;
  final Offset offset;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final shadow = Path.combine(
      PathOperation.difference,
      Path()..addRRect(slot),
      Path()..addRRect(slot.shift(offset)),
    );
    canvas.drawPath(shadow, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_InsetShadowPainter oldDelegate) =>
      color != oldDelegate.color ||
      offset != oldDelegate.offset ||
      radius != oldDelegate.radius;
}
