import 'dart:async';

import 'package:flutter/widgets.dart';

mixin BrutalPressFeedback<T extends StatefulWidget> on State<T> {
  static const Duration pressAnimationDuration = Duration(milliseconds: 40);
  static const Duration minimumPressedDuration = Duration(milliseconds: 100);

  bool isPressed = false;
  bool _fingerDown = false;

  // Runs for [minimumPressedDuration] after a press. A Timer (not the wall
  // clock) so a quick tap still shows the pressed state, also in tests.
  Timer? _minimumTimer;

  bool get isPressEnabled;

  @override
  void dispose() {
    _minimumTimer?.cancel();
    super.dispose();
  }

  Widget pressListener({required Widget child}) => Listener(
    onPointerDown: (_) => _press(),
    onPointerUp: (_) => _release(),
    onPointerCancel: (_) => _release(),
    child: child,
  );

  // Sinks the button and keeps it down for at least the minimum time.
  void _press() {
    if (!isPressEnabled) return;
    _fingerDown = true;
    _minimumTimer?.cancel();
    _minimumTimer = Timer(minimumPressedDuration, () {
      _minimumTimer = null;
      if (!_fingerDown && mounted) setState(() => isPressed = false);
    });
    if (!isPressed) setState(() => isPressed = true);
  }

  // Lifts the button now, or when the minimum time is over.
  void _release() {
    if (!isPressed) return;
    _fingerDown = false;
    if (_minimumTimer == null) setState(() => isPressed = false);
  }
}
