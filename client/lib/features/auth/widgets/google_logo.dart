import 'package:flutter/widgets.dart';

class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 22});

  static const String assetPath = 'assets/google_logo.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}
