import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'brutal_badge.dart';

extension ChronotypePresentation on Chronotype {
  String get displayName => switch (this) {
    Chronotype.lion => 'Sư tử',
    Chronotype.bear => 'Gấu',
    Chronotype.wolf => 'Sói',
  };

  Color get badgeColor => switch (this) {
    Chronotype.lion => AppColors.sunflower,
    Chronotype.bear => AppColors.lime,
    Chronotype.wolf => AppColors.slate,
  };

  Color get badgeForegroundColor => switch (this) {
    Chronotype.wolf => AppColors.onSlate,
    Chronotype.lion || Chronotype.bear => AppColors.ink,
  };

  IconData get icon => switch (this) {
    Chronotype.lion => Icons.wb_sunny_rounded,
    Chronotype.bear => Icons.wb_cloudy_rounded,
    Chronotype.wolf => Icons.nightlight_round,
  };
}

class ChronotypeBadge extends StatelessWidget {
  const ChronotypeBadge({super.key, required this.chronotype});

  final Chronotype chronotype;

  @override
  Widget build(BuildContext context) {
    return BrutalBadge(
      label: chronotype.displayName,
      icon: chronotype.icon,
      color: chronotype.badgeColor,
      foregroundColor: chronotype.badgeForegroundColor,
    );
  }
}
