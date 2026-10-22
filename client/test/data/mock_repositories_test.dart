import 'dart:typed_data';

import 'package:client/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppRepositories repos;

  setUp(() => repos = AppRepositories.mock());

  test('read-only endpoints return sample data', () async {
    expect((await repos.auth.signInWithGoogle('code')).isNewUser, isFalse);
    expect((await repos.user.getMe()).email, isNotEmpty);
    expect(await repos.sleep.getHealthProfile(), isNotNull);
    expect((await repos.sleep.getSleepDebt()).daily, hasLength(7));
    expect((await repos.sleep.getBiorhythm(DateTime.now())).points, isNotEmpty);
    expect((await repos.calendarSync.getStatus()).connected, isTrue);
    expect(await repos.calendarSync.listConflicts(), hasLength(1));
    expect((await repos.reminders.randomQuote()).text, isNotEmpty);
    final voice = await repos.voice.transcribe(Uint8List(1), filename: 'a.m4a');
    expect(voice.todoDraft, isNotNull);
  });

  test('events of the current week', () async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final events = await repos.events.listEvents(
      from: monday,
      to: monday.add(const Duration(days: 7)),
    );
    expect(events.where((e) => e.source == EventSource.ocr), hasLength(4));
  });

  test('todo CRUD and filters', () async {
    final open = await repos.todos.listTodos(
      query: const TodoQuery(status: TodoStatus.todo),
    );
    expect(open.items.every((t) => t.status == TodoStatus.todo), isTrue);

    final created = await repos.todos.createTodo(
      const TodoCreate(title: 'Làm lab 4', category: TodoCategory.assignment),
    );
    final done = await repos.todos.updateTodo(
      created.id,
      const TodoUpdate(status: TodoStatus.done, description: Nullable(null)),
    );
    expect(done.status, TodoStatus.done);
    expect(done.title, 'Làm lab 4');

    await repos.todos.deleteTodo(created.id);
    await expectLater(
      repos.todos.getTodo(created.id),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'TODO_NOT_FOUND'),
      ),
    );
  });

  test('OCR success, failure and saving subjects', () async {
    final job = await repos.timetable.uploadTimetablePhoto(
      Uint8List(1),
      filename: 'tkb.jpg',
    );
    final result = await repos.timetable.getOcrJob(job.jobId);
    expect(result.status, JobStatus.succeeded);
    expect(result.subjects, isNotEmpty);

    final failJob = await repos.timetable.uploadTimetablePhoto(
      Uint8List(1),
      filename: 'fail.jpg',
    );
    final failed = await repos.timetable.getOcrJob(failJob.jobId);
    expect(failed.error, 'OCR_NO_TABLE_FOUND');

    await repos.timetable.saveSubjects(result.subjects, replaceExisting: true);
    expect(
      await repos.timetable.listSubjects(),
      hasLength(result.subjects.length),
    );
  });

  test('sleep log edit recomputes duration', () async {
    final log = await repos.sleep.createSleepLog(
      SleepLogCreate(
        sleepAt: DateTime(2026, 10, 21, 23),
        wakeAt: DateTime(2026, 10, 22, 7),
      ),
    );
    expect(log.durationMinutes, 480);
    final edited = await repos.sleep.updateSleepLog(
      log.id,
      SleepLogUpdate(wakeAt: DateTime(2026, 10, 22, 6)),
    );
    expect(edited.durationMinutes, 420);
  });

  test('schedule apply returns the chosen blocks as events', () async {
    final suggestion = await repos.schedule.generate(
      ScheduleRequest(from: DateTime.now(), to: DateTime.now()),
    );
    final events = await repos.schedule.apply(
      suggestion.suggestionId,
      blockIndexes: [0],
    );
    expect(events.single.title, suggestion.blocks.first.title);
  });
}
