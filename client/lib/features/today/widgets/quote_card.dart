import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.text, this.onTap});

  static const String fallbackText = 'Ngủ đủ cũng là một phần của việc học.';

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = _buildCard();
    final onTap = this.onTap;
    if (onTap == null) return card;
    return Semantics(
      button: true,
      hint: 'Xem tiến độ tuần này',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }

  Widget _buildCard() {
    return BrutalCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“',
            style: AppTypography.title.copyWith(fontSize: 32, height: 1),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
}
