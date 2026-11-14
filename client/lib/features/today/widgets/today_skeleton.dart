import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class TodaySkeleton extends StatelessWidget {
  const TodaySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Đang tải dữ liệu hôm nay',
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Block(width: 220, height: 26),
                      SizedBox(height: AppSpacing.xs),
                      _Block(width: 120, height: 26),
                    ],
                  ),
                ),
                _Block(width: 48, height: 48, isRound: true),
              ],
            ),
            SizedBox(height: AppSpacing.lg),
            BrutalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Block(width: 150, height: 12),
                  SizedBox(height: AppSpacing.sm),
                  _Block(width: 110, height: 36),
                  SizedBox(height: AppSpacing.sm),
                  _Block(height: 12),
                  SizedBox(height: AppSpacing.sm),
                  _Block(width: 150, height: 16),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.md),
            BrutalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Block(width: 100, height: 12),
                  SizedBox(height: AppSpacing.sm),
                  _Block(width: 170, height: 36),
                  SizedBox(height: AppSpacing.sm),
                  _Block(width: 120, height: 12),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: _Block(width: 130, height: 18),
            ),
            SizedBox(height: AppSpacing.md),
            _TimelineRowBlock(),
            _TimelineRowBlock(),
            _TimelineRowBlock(),
            _TimelineRowBlock(),
          ],
        ),
      ),
    );
  }
}

class _TimelineRowBlock extends StatelessWidget {
  const _TimelineRowBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          _Block(width: 40, height: 12),
          SizedBox(width: AppSpacing.md),
          Expanded(child: _Block(height: 40)),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.width, required this.height, this.isRound = false});

  final double? width;
  final double height;
  final bool isRound;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.skeleton,
        borderRadius: BorderRadius.circular(isRound ? height / 2 : 8),
      ),
    );
  }
}
