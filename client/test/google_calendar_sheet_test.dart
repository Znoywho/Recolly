import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/sync/calendar_push_page.dart';
import 'package:client/features/sync/google_calendar_sheet.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('one-way is the default and the user picks the sync mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repos = AppRepositories.mock();

    await tester.pumpWidget(
      RepositoryScope(
        repositories: repos,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: GoogleCalendarSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Opening the sheet no longer switches two-way on by itself,
    // but still clears the waiting conflicts (the mock starts with one).
    expect((await repos.calendarSync.getStatus()).syncMode, SyncMode.push);
    expect(await repos.calendarSync.listConflicts(), isEmpty);
    expect(find.text('Một chiều: app → Google'), findsOneWidget);

    await tester.tap(find.text('Hai chiều'));
    await tester.pumpAndSettle();
    expect((await repos.calendarSync.getStatus()).syncMode, SyncMode.twoWay);

    await tester.tap(find.text('Tạm dừng'));
    await tester.pumpAndSettle();
    expect((await repos.calendarSync.getStatus()).syncMode, SyncMode.off);
    expect(find.text('Đang tạm dừng'), findsOneWidget);
    final syncNow = tester.widget<BrutalButton>(
      find.widgetWithText(BrutalButton, 'Đồng bộ ngay'),
    );
    expect(syncNow.onPressed, isNull); // nothing to sync while paused
    await tester.tap(find.text('3 sự kiện chờ'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarPushPage), findsNothing);
  });
}
