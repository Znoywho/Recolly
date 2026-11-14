import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/sleep/sleep_page.dart';
import 'package:client/features/sleep/widgets/bedtime_card.dart';
import 'package:client/features/sleep/widgets/sleep_debt_hero_card.dart';
import 'package:client/features/today/widgets/barchat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(AppRepositories repositories) => RepositoryScope(
  repositories: repositories,
  child: MaterialApp(
    theme: AppTheme.light(),
    home: const Scaffold(body: SleepPage()),
  ),
);

void main() {
  testWidgets('SleepPage shows debt, weekly chart and bedtime from mock data', (
    tester,
  ) async {
    await tester.pumpWidget(_app(AppRepositories.mock()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Giấc ngủ'), findsOneWidget);
    expect(find.byType(SleepDebtHeroCard), findsOneWidget);
    expect(find.byType(WeeklySleepBarChart), findsOneWidget);
    expect(find.byType(BedtimeCard), findsOneWidget);
  });

  testWidgets('tapping the reminder button turns the bedtime reminder on', (
    tester,
  ) async {
    final repositories = AppRepositories.mock();
    final before = await repositories.reminders.getSettings();
    await repositories.reminders.saveSettings(
      ReminderSettings.fromJson({
        ...before.toJson(),
        'bedtime_reminder_enabled': false,
      }),
    );

    await tester.pumpWidget(_app(repositories));
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Đặt nhắc nhở'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đặt nhắc nhở'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Đã bật nhắc nhở'), findsOneWidget);
    expect(
      (await repositories.reminders.getSettings()).bedtimeReminderEnabled,
      isTrue,
    );
  });
}
