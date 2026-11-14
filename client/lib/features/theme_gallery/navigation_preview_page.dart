import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';
import '../calendar/calendar_page_demo.dart';
import '../personal/personal_page.dart';
import '../sleep/sleep_page.dart';
import '../today/today_page.dart';

class NavigationPreviewPage extends StatefulWidget {
  const NavigationPreviewPage({super.key});

  @override
  State<NavigationPreviewPage> createState() => _NavigationPreviewPageState();
}

class _NavigationPreviewPageState extends State<NavigationPreviewPage> {
  BrutalNavTab _currentTab = BrutalNavTab.today;

  void _selectTab(BrutalNavTab tab) => setState(() => _currentTab = tab);

  Widget _pageFor(BrutalNavTab tab) => switch (tab) {
    BrutalNavTab.today => TodayPage(
      onProfilePressed: () => _selectTab(BrutalNavTab.personal),
    ),
    BrutalNavTab.calendar => const CalendarPage(),
    BrutalNavTab.sleep => const SleepPage(),
    BrutalNavTab.personal => const PersonalPage(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentTab.index,
        children: [for (final tab in BrutalNavTab.values) _pageFor(tab)],
      ),
      bottomNavigationBar: BrutalBottomNavBar(
        currentTab: _currentTab,
        onTabSelected: _selectTab,
      ),
    );
  }
}
