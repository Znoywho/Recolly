import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

class GallerySection extends StatelessWidget {
  const GallerySection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.subtitle),
          const SizedBox(height: AppSpacing.sm),
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            child,
          ],
        ],
      ),
    );
  }
}
