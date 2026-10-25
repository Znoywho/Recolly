import 'package:client/app.dart';
import 'package:client/data/data.dart';
import 'package:client/features/theme_gallery/widgets/alertness_score_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RecollyApp opens the theme gallery and loads mock overview', (
    tester,
  ) async {
    await tester.pumpWidget(RecollyApp(repositories: AppRepositories.mock()));

    expect(find.text('Recolly · Design system'), findsOneWidget);
    expect(find.text('Đang tải dữ liệu…'), findsWidgets);

    await tester.pump(const Duration(seconds: 1));

    final liveCard = tester.widget<AlertnessScoreCard>(
      find.byType(AlertnessScoreCard).first,
    );
    expect(liveCard.snapshot, isA<AlertnessReady>());
  });
}
