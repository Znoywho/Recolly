import 'dart:async';

import 'package:flutter/widgets.dart';

mixin BrutalPressFeedback<T extends StatefulWidget> on State<T> {
  static const Duration pressAnimationDuration = Duration(milliseconds: 40);
  static const Duration minimumPressedDuration = Duration(milliseconds: 100);

  bool isPressed = false;
  DateTime? _pressedAt;
  Timer? _releaseTimer;

  bool get isPressEnabled;

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  Widget pressListener({required Widget child}) => Listener(
    onPointerDown: (_) => _press(),
    onPointerUp: (_) => _release(),
    onPointerCancel: (_) => _release(),
    child: child,
  );

  void _press() {
    if (!isPressEnabled) return;
    _releaseTimer?.cancel();
    _pressedAt = DateTime.now();
    if (!isPressed) setState(() => isPressed = true);
  }

  void _release() {
    final pressedAt = _pressedAt;
    if (!isPressed || pressedAt == null) return;
    final remaining =
        minimumPressedDuration - DateTime.now().difference(pressedAt);
    _releaseTimer?.cancel();
    if (remaining <= Duration.zero) {
      setState(() => isPressed = false);
      return;
    }
    _releaseTimer = Timer(remaining, () {
      if (mounted) setState(() => isPressed = false);
    });
  }
}
