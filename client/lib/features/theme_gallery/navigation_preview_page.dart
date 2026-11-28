import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';
import '../add/add_schedule_sheet.dart';
import '../calendar/week_calendar_page.dart';
import '../personal/personal_page.dart';
import '../sleep/sleep_page.dart';
import '../timetable/timetable_import_page.dart';
import '../today/today_page.dart';

class NavigationPreviewPage extends StatefulWidget {
  const NavigationPreviewPage({super.key});

  @override
  State<NavigationPreviewPage> createState() => _NavigationPreviewPageState();
}

class _NavigationPreviewPageState extends State<NavigationPreviewPage> {
  BrutalNavTab _currentTab = BrutalNavTab.today;
  final Set<BrutalNavTab> _openedTabs = {BrutalNavTab.today};

  // Bumped after something is added, so the open tabs load their data again.
  int _reloadTick = 0;

  // Opens the "Thêm lịch" sheet and reloads the tabs if something was saved.
  Future<void> _add() async {
    if (await showAddScheduleSheet(context)) setState(() => _reloadTick++);
  }

  void _selectTab(BrutalNavTab tab) => setState(() {
    _currentTab = tab;
    _openedTabs.add(tab);
  });

  Widget _pageFor(BrutalNavTab tab) => switch (tab) {
    BrutalNavTab.today => TodayPage(
      onProfilePressed: () => _selectTab(BrutalNavTab.personal),
    ),
    BrutalNavTab.calendar => WeekCalendarPage(
      onImportTimetable: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TimetableImportPage()),
      ),
    ),
    BrutalNavTab.sleep => const SleepPage(),
    BrutalNavTab.personal => const PersonalPage(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: KeyedSubtree(
        key: ValueKey(_reloadTick),
        child: IndexedStack(
          index: _currentTab.index,
          children: [
            for (final tab in BrutalNavTab.values)
              _openedTabs.contains(tab)
                  ? _pageFor(tab)
                  : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: BrutalBottomNavBar(
        currentTab: _currentTab,
        onTabSelected: _selectTab,
        onAddPressed: _add,
      ),
    );
  }
}
