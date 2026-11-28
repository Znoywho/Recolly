import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/add/add_schedule_sheet.dart';
import 'package:client/features/timetable/subject_form_page.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Phone-sized app with mock data around [home].
Future<AppRepositories> pumpApp(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repositories = AppRepositories.mock();
  await tester.pumpWidget(
    RepositoryScope(
      repositories: repositories,
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ),
  );
  return repositories;
}

void main() {
  testWidgets('nav bar shows the "+" only when onAddPressed is set', (
    tester,
  ) async {
    var pressed = 0;
    Widget bar(VoidCallback? onAdd) => Scaffold(
      bottomNavigationBar: BrutalBottomNavBar(
        currentTab: BrutalNavTab.today,
        onTabSelected: (_) {},
        onAddPressed: onAdd,
      ),
    );

    await pumpApp(tester, bar(null));
    expect(find.bySemanticsLabel('Thêm lịch'), findsNothing);

    await pumpApp(tester, bar(() => pressed++));
    await tester.tap(find.bySemanticsLabel('Thêm lịch'));
    expect(pressed, 1);
  });

  testWidgets('"Nhập tay" → "Môn học" opens the subject form', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAddScheduleSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Môn học'), findsNothing);

    await tester.tap(find.text('Nhập tay'));
    await tester.pump();
    await tester.tap(find.text('Môn học'));
    await tester.pumpAndSettle();
    expect(find.byType(SubjectFormPage), findsOneWidget);
  });

  testWidgets('subject form adds one session per day, keeps the timetable', (
    tester,
  ) async {
    final repos = await pumpApp(tester, const SubjectFormPage());
    final before = (await repos.timetable.listSubjects()).length;

    // Nothing filled in: not saved, a hint is shown.
    await tester.tap(find.text('Lưu'));
    await tester.pump();
    expect(find.text('Nhập tên môn trước nhé'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Kinh tế vĩ mô');
    await tester.tap(find.text('T2'));
    await tester.tap(find.text('T4'));
    await tester.pump();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    final after = await repos.timetable.listSubjects();
    expect(after.length, before + 2);
    expect(
      after.where((s) => s.name == 'Kinh tế vĩ mô').map((s) => s.dayOfWeek),
      [1, 3],
    );
  });
}
