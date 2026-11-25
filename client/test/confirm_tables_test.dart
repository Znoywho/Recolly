import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/timetable/scan_result_page.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SubjectDraft _subject(String name, {double? confidence}) => SubjectDraft(
  name: name,
  room: 'B1.02',
  dayOfWeek: 2,
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
}
