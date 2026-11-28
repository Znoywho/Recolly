import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/timetable/scan_result_page.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SubjectDraft _subject(String name, {double? confidence, int day = 2}) =>
    SubjectDraft(
      name: name,
      room: 'B1.02',
      dayOfWeek: day,
      startTime: const ClockTime(7, 30),
      endTime: const ClockTime(9, 30),
      startDate: DateTime(2026, 9, 7),
      endDate: DateTime(2026, 12, 20),
      confidence: confidence,
    );

void main() {
  testWidgets('OCR result saves only the ticked subjects', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repositories = AppRepositories.mock();
    await tester.pumpWidget(
      RepositoryScope(
        repositories: repositories,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ScanResultPage(
            subjects: [
              _subject('Cấu trúc dữ liệu'),
              _subject('Toán rời rạc', confidence: 0.4),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Cấu trúc dữ liệu'), findsOneWidget);
    expect(find.text('Đúng rồi, lưu 2 môn'), findsOneWidget);

    // Untick the low-confidence row.
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(find.text('Đúng rồi, lưu 1 môn'), findsOneWidget);

    await tester.tap(find.text('Đúng rồi, lưu 1 môn'));
    await tester.pumpAndSettle();
    if (find.text('Thay thế').evaluate().isNotEmpty) {
      await tester.tap(find.text('Thay thế'));
      await tester.pumpAndSettle();
    }

    final saved = await repositories.timetable.listSubjects();
    expect(saved.map((s) => s.name), ['Cấu trúc dữ liệu']);
  });

  testWidgets('confirm table shows headers, cells and checkbox state', (
    tester,
  ) async {
    var picked = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BrutalConfirmTable(
              headers: const ['Mục', 'Máy hiểu là'],
              rows: [
                ConfirmRow(
                  cells: const ['Tên việc', 'Nộp báo cáo'],
                  selected: picked,
                  onSelected: (v) => setState(() => picked = v),
                ),
                const ConfirmRow(cells: ['Hạn chót', 'Chưa có']),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Máy hiểu là'), findsOneWidget);
    expect(find.text('Nộp báo cáo'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(picked, isFalse);
  });

  testWidgets('sessions of one subject share a card and are saved together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repositories = AppRepositories.mock();
    await tester.pumpWidget(
      RepositoryScope(
        repositories: repositories,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ScanResultPage(
            subjects: [
              _subject('English', day: 4),
              _subject('Tư tưởng HCM', day: 4),
              _subject('English', day: 6),
            ],
          ),
        ),
      ),
    );

    expect(find.text('English'), findsOneWidget);
    expect(find.text('T5 07:30–09:30'), findsNWidgets(2));
    expect(find.text('T7 07:30–09:30'), findsOneWidget);
    expect(find.text('Đúng rồi, lưu 2 môn'), findsOneWidget);

    // Untick English: both of its sessions go.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('Đúng rồi, lưu 1 môn'));
    await tester.pumpAndSettle();
    if (find.text('Thay thế').evaluate().isNotEmpty) {
      await tester.tap(find.text('Thay thế'));
      await tester.pumpAndSettle();
    }

    final saved = await repositories.timetable.listSubjects();
    expect(saved.map((s) => s.name), ['Tư tưởng HCM']);
  });

  test('a one-week session becomes a 15-week semester', () {
    final oneDay = SubjectDraft(
      name: 'English',
      dayOfWeek: 4,
      startTime: const ClockTime(6, 45),
      endTime: const ClockTime(9, 15),
      startDate: DateTime(2026, 11, 26),
      endDate: DateTime(2026, 11, 26),
    );
    final stretched = stretchOneDay(oneDay);
    expect(stretched.startDate, DateTime(2026, 11, 26));
    expect(
      stretched.endDate,
      DateTime(2026, 11, 26).add(const Duration(days: 105)),
    );
    expect(stretchOneDay(stretched).endDate, stretched.endDate);
  });

  test('short labels for rooms and days', () {
    expect(shortRoom('E204 - CS1 (P.Thạnh Mỹ Tây, TP.HCM)'), 'E204');
    expect(shortRoom('B1.02'), 'B1.02');
    expect(shortDayName(1), 'T2');
    expect(shortDayName(6), 'T7');
    expect(shortDayName(7), 'CN');
  });
}
