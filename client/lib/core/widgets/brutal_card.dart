import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

class BrutalCard extends StatelessWidget {
  const BrutalCard({
    super.key,
    required this.child,
    this.color = AppColors.paper,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.borderRadius = AppRadii.mdAll,
    this.shadowOffset = AppShadows.regularOffset,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BrutalDecoration.box(
        color: color,
        borderRadius: borderRadius,
        shadowOffset: shadowOffset,
      ),
      child: child,
    );
  }
}
