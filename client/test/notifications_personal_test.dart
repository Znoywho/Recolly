import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/notifications/notifications_data.dart';
import 'package:client/features/notifications/notifications_page.dart';
import 'package:client/features/personal/personal_page.dart';
import 'package:client/features/today/today_page.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<Size> _screenSizes = [
  Size(320, 568),
  Size(393, 852),
  Size(768, 1024),
  Size(640, 360),
];

Future<void> _loadAppFont() async {
  final loader = FontLoader(AppTypography.fontFamily);
  for (final weight in ['Regular', 'SemiBold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
  }
  await loader.load();
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget home, {
  AppRepositories? repositories,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepositoryScope(
      repositories: repositories ?? AppRepositories.mock(),
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

Widget _personalTab() => Scaffold(
  extendBody: true,
  body: const PersonalPage(),
  bottomNavigationBar: BrutalBottomNavBar(
    currentTab: BrutalNavTab.personal,
    onTabSelected: (_) {},
  ),
);

void main() {
  setUpAll(_loadAppFont);

  for (final size in _screenSizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('NotificationsPage has no overflow at $label', (tester) async {
      await _pumpAt(tester, size, const NotificationsPage());

      expect(find.text('Thông báo'), findsOneWidget);
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PersonalPage has no overflow at $label', (tester) async {
      await _pumpAt(tester, size, _personalTab());

      expect(find.text('Cá nhân'), findsWidgets);
      expect(find.text('Nguyễn Văn A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bell on Today opens the notifications page', (tester) async {
    await _pumpAt(
      tester,
      const Size(393, 852),
      const Scaffold(body: TodayPage()),
    );

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.text('Thông báo'), findsOneWidget);
  });

  testWidgets('filter chips narrow the notification list', (tester) async {
    await _pumpAt(tester, const Size(393, 852), const NotificationsPage());

    await tester.tap(find.text('Giấc ngủ'));
    await tester.pump();

    expect(find.text('Đến giờ đi ngủ rồi'), findsOneWidget);
    expect(find.textContaining('hết hạn sau'), findsNothing);
  });

  testWidgets('turning off bedtime reminder hides the bedtime notification', (
    tester,
  ) async {
    final repositories = AppRepositories.mock();
    await _pumpAt(
      tester,
      const Size(393, 852),
      _personalTab(),
      repositories: repositories,
    );

    final bedtimeSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Nhắc đi ngủ'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(bedtimeSwitch).value, isTrue);

    await tester.tap(bedtimeSwitch);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.widget<Switch>(bedtimeSwitch).value, isFalse);
    final saved = await repositories.reminders.getSettings();
    expect(saved.bedtimeReminderEnabled, isFalse);

    final data = await NotificationsData.load(repositories);
    expect(
      data.notifications.where((n) => n.category == NotificationCategory.sleep),
      isEmpty,
    );
  });

  test('remaining deadline label uses days, hours, then minutes', () {
    expect(NotificationsData.remainingLabel(const Duration(days: 2)), '2 ngày');
    expect(NotificationsData.remainingLabel(const Duration(hours: 3)), '3 giờ');
    expect(
      NotificationsData.remainingLabel(const Duration(minutes: 20)),
      '20 phút',
    );
  });
}
