import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum BrutalNavTab {
  today('Hôm nay', Icons.home_outlined),
  calendar('Lịch', Icons.calendar_month_outlined),
  sleep('Giấc ngủ', Icons.bedtime_outlined),
  personal('Cá nhân', Icons.person_outline_rounded);

  const BrutalNavTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class BrutalBottomNavBar extends StatelessWidget {
  const BrutalBottomNavBar({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
  });

  final BrutalNavTab currentTab;
  final ValueChanged<BrutalNavTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: AppTheme.brutalBox(borderRadius: AppRadii.pillAll),
        child: Row(
          children: [
            for (final tab in BrutalNavTab.values)
              Expanded(
                child: _NavItem(
                  tab: tab,
                  isSelected: tab == currentTab,
                  onTap: () => onTabSelected(tab),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final BrutalNavTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs - 2),
          decoration: AppTheme.brutalBox(
            color: isSelected ? AppColors.teal : AppColors.white,
            borderRadius: AppRadii.pillAll,
            hasBorder: isSelected,
            hasShadow: false,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 22),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
