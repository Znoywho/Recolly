import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/sleep/sleep_page.dart';
import 'package:client/features/sleep/sleep_profile_page.dart';
import 'package:client/features/sleep/widgets/sleep_empty_card.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<Size> _screenSizes = [
  Size(320, 568),
  Size(360, 640),
  Size(393, 852),
  Size(430, 932),
  Size(768, 1024),
  Size(1024, 768),
  Size(640, 360),
];

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget home, {
  AppRepositories? repositories,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepositoryScope(
      repositories: repositories ?? AppRepositories.mock(),
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

Widget _sleepTab() => Scaffold(
  extendBody: true,
  body: const SleepPage(),
  bottomNavigationBar: BrutalBottomNavBar(
    currentTab: BrutalNavTab.sleep,
    onTabSelected: (_) {},
  ),
);

void main() {
  for (final size in _screenSizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('SleepProfilePage has no overflow at $label', (tester) async {
      await _pumpAt(tester, size, const SleepProfilePage());

      expect(find.text('Ngày đi học'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SleepPage has no overflow at $label', (tester) async {
      await _pumpAt(tester, size, _sleepTab());

      expect(find.text('Giấc ngủ'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SleepEmptyCard has no overflow at $label', (tester) async {
      await _pumpAt(
        tester,
        size,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [SleepEmptyCard(onLogSleep: () {})],
          ),
        ),
      );

      expect(find.text('Chưa có dữ liệu giấc ngủ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('both sleep screens survive 1.3x text scale on a small phone', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const Size(360, 640),
      const SleepProfilePage(),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);

    await _pumpAt(tester, const Size(360, 640), _sleepTab(), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SleepProfilePage sends the MCTQ answers and saves them', (
    tester,
  ) async {
    final repositories = AppRepositories.mock();
    HealthProfile? completed;
    await _pumpAt(
      tester,
      const Size(393, 852),
      SleepProfilePage(onCompleted: (profile) => completed = profile),
      repositories: repositories,
    );

    Future<void> tapText(String text) async {
      await tester.ensureVisible(find.text(text).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).first);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.bySemanticsLabel('4 ngày đi học'));
    await tester.tap(find.byTooltip('Thức dậy lúc: muộn hơn 15 phút'));
    await tapText('Tiếp tục');
    expect(find.text('Ngày nghỉ'), findsOneWidget);
    await tapText('Tiếp tục');

    // 3+ nights asks how long it has lasted before scoring.
    await tester.tap(find.bySemanticsLabel('Khó ngủ 3+ đêm'));
    await tester.pump();
    expect(find.text('Tình trạng này kéo dài bao lâu rồi?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Kéo dài >3m'));
    await tapText('Xem con vật của bạn');

    expect(find.text('Bạn là Gấu!'), findsOneWidget);
    expect(find.byType(AnimalMascot), findsWidgets);
    await tapText('Lưu và tiếp tục');

    expect(completed, isNotNull);
    expect(completed!.mctq?.workDays, 4);
    expect(completed!.usualWakeTime, const ClockTime(6, 45));
    expect(completed!.sleepQuality?.duration, ProblemDuration.overThreeMonths);
  });

  testWidgets('wake time wraps around midnight', (tester) async {
    await _pumpAt(tester, const Size(393, 852), const SleepProfilePage());

    // The wake-up card is the second clock on the school-day step.
    String shownWakeTime() => tester
        .widgetList<Text>(find.textContaining(RegExp(r'^\d\d:\d\d$')))
        .last
        .data!;
    final before = shownWakeTime();
    final earlier = find.byTooltip('Thức dậy lúc: sớm hơn 15 phút');
    for (var i = 0; i < 4 * 24; i++) {
      await tester.tap(earlier);
      await tester.pump();
    }
    await tester.pump();

    expect(shownWakeTime(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every mascot paints without errors', (tester) async {
    await _pumpAt(
      tester,
      const Size(393, 852),
      Scaffold(
        body: Wrap(
          children: [
            for (final animal in MascotAnimal.values)
              AnimalMascot(animal: animal),
          ],
        ),
      ),
    );
    expect(find.byType(AnimalMascot), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
