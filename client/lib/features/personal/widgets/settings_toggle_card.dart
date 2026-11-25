import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';

class SettingsToggle {
  const SettingsToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
}

class SettingsToggleCard extends StatelessWidget {
  const SettingsToggleCard({super.key, required this.toggles});

  final List<SettingsToggle> toggles;

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final toggle in toggles) ...[
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(toggle.label, style: AppTypography.body),
                    ),
                    Switch(value: toggle.value, onChanged: toggle.onChanged),
                  ],
                ),
              ),
            ),
            if (toggle != toggles.last) const Divider(height: AppBorders.width),
          ],
        ],
      ),
    );
  }
}
