import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/today/biorhythm_page.dart';
import 'package:client/features/today/today_page.dart';
import 'package:client/features/today/widgets/barchat.dart';
import 'package:client/features/today/widgets/motivation_dialog.dart';
import 'package:client/features/today/widgets/quote_card.dart';
import 'package:client/features/today/widgets/alertness_score_card.dart';
import 'package:client/features/today/widgets/today_skeleton.dart';
import 'package:client/features/today/widgets/today_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TodayPage shows a skeleton, then the mock overview', (
    tester,
  ) async {
    await tester.pumpWidget(
      RepositoryScope(
        repositories: AppRepositories.mock(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: TodayPage()),
        ),
      ),
    );

    expect(find.byType(TodaySkeleton), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(TodaySkeleton), findsNothing);
    expect(find.text('Lịch hôm nay'), findsOneWidget);
    expect(find.text('Nợ giấc ngủ'), findsOneWidget);
    final card = tester.widget<AlertnessScoreCard>(
      find.byType(AlertnessScoreCard),
    );
    expect(card.snapshot, isA<AlertnessReady>());
    expect(find.byType(TodayTimeline), findsOneWidget);
  });

  testWidgets('tapping the alertness card opens the biorhythm screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      RepositoryScope(
        repositories: AppRepositories.mock(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: TodayPage()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byType(AlertnessScoreCard));
    await tester.pumpAndSettle();

    expect(find.byType(BiorhythmPage), findsOneWidget);
    expect(find.byType(DailyEnergyChart), findsOneWidget);
    expect(find.text('Học theo nhịp của bạn'), findsOneWidget);
  });

  testWidgets('tapping the quote card opens the motivation popup', (
    tester,
  ) async {
    await tester.pumpWidget(
      RepositoryScope(
        repositories: AppRepositories.mock(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: TodayPage()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.byType(QuoteCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(QuoteCard));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MotivationDialog), findsOneWidget);
    expect(find.text(MotivationDialog.headline), findsOneWidget);

    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    expect(find.byType(MotivationDialog), findsNothing);
  });
}
