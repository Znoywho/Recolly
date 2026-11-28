import 'package:client/core/di/repository_scope.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/data.dart';
import 'package:client/features/sleep/sleep_log_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 27);

  test('bedtime after wake time means the evening before', () {
    final (sleepAt, wakeAt) = sleepWindow(
      day,
      const TimeOfDay(hour: 23, minute: 30),
      const TimeOfDay(hour: 7, minute: 0),
    );
    expect(sleepAt, DateTime(2026, 11, 26, 23, 30));
    expect(wakeAt, DateTime(2026, 11, 27, 7, 0));
  });

  test('bedtime after midnight and naps stay on the same day', () {
    final (late, _) = sleepWindow(
      day,
      const TimeOfDay(hour: 0, minute: 30),
      const TimeOfDay(hour: 7, minute: 0),
    );
    expect(late, DateTime(2026, 11, 27, 0, 30));

    final (nap, napEnd) = sleepWindow(
      day,
      const TimeOfDay(hour: 13, minute: 0),
      const TimeOfDay(hour: 14, minute: 0),
    );
    expect(napEnd.difference(nap), const Duration(hours: 1));
  });

  test('same limits as the server: 16 h max, no future wake time', () {
    final now = DateTime(2026, 11, 27, 9);
    expect(
      sleepProblem(DateTime(2026, 11, 26, 23), DateTime(2026, 11, 27, 7), now),
      isNull,
    );
    // 13:00 → 07:00 next day is 18 h.
    expect(
      sleepProblem(DateTime(2026, 11, 26, 13), DateTime(2026, 11, 27, 7), now),
      isNotNull,
    );
    // Waking at 10:00 when it is 09:00.
    expect(
      sleepProblem(DateTime(2026, 11, 27, 1), DateTime(2026, 11, 27, 10), now),
      isNotNull,
    );
  });

  testWidgets('saving sends one sleep log and closes the form', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repos = AppRepositories.mock();
    final before = (await repos.sleep.listSleepLogs()).length;

    Object? popped;
    await tester.pumpWidget(
      RepositoryScope(
        repositories: repos,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => popped = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SleepLogFormPage()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tốt'));
    await tester.pump();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    final logs = await repos.sleep.listSleepLogs();
    expect(logs.length, before + 1);
  });
}
