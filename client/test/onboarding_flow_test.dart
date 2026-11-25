import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/calendar/week_calendar_page.dart';
import 'package:client/features/sleep/sleep_profile_page.dart';
import 'package:client/features/sync/google_calendar_sheet.dart';
import 'package:client/features/theme_gallery/navigation_preview_page.dart';
import 'package:client/features/timetable/timetable_import_page.dart';
import 'package:client/features/welcome_screens/startscreen.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadAppFont() async {
  final loader = FontLoader(AppTypography.fontFamily);
  for (final weight in ['Regular', 'SemiBold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadAppFont);

  testWidgets('Bắt đầu opens the sleep profile, then the timetable import', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repositories = AppRepositories.mock();
    await tester.pumpWidget(
      RepositoryScope(
        repositories: repositories,
        child: MaterialApp(theme: AppTheme.light(), home: const Startscreen()),
      ),
    );

    await tester.tap(find.text('Bắt đầu'));
    await tester.pumpAndSettle();
    expect(find.byType(SleepProfilePage), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Trước 23h'));
    await tester.pump();
    await tester.ensureVisible(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    expect(find.byType(TimetableImportPage), findsOneWidget);
    final saved = await repositories.sleep.getHealthProfile();
    expect(saved?.chronotype, Chronotype.lion);
  });

  testWidgets(
    'Calendar tab shows the week calendar, Personal tab opens Google Calendar',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepositoryScope(
          repositories: AppRepositories.mock(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const NavigationPreviewPage(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.bySemanticsLabel('Lịch'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(WeekCalendarPage), findsOneWidget);
      expect(find.byType(BrutalBottomNavBar), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Cá nhân'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Tài khoản Google'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GoogleCalendarSheet), findsOneWidget);
    },
  );
}
