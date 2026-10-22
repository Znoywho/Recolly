import 'dart:typed_data';

import '../api/api_exception.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/calendar_sync_repository.dart';
import '../repositories/event_repository.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/schedule_repository.dart';
import '../repositories/sleep_repository.dart';
import '../repositories/timetable_repository.dart';
import '../repositories/todo_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/voice_repository.dart';

/// Mock repositories with fixed sample data, for building screens before the
/// backend endpoints exist. Lists that screens edit (todos, events, subjects,
/// sleep logs) are kept in memory; everything else returns the same sample.
/// Dates are placed around the current week so the calendar is not empty.

/// Base for mock repositories: simulated latency and shared helpers.
abstract class _Mock {
  _Mock(this.latency);

  final Duration latency;
  int _seq = 0;

  Future<void> delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  String newId() => 'mock-${runtimeType.toString().toLowerCase()}-${++_seq}';

  ApiException notFound(String code) =>
      ApiException(statusCode: 404, code: code, message: 'Not found');

  int indexOf<T>(
    List<T> items,
    String Function(T) id,
    String key,
    String code,
  ) {
    final i = items.indexWhere((e) => id(e) == key);
    if (i < 0) throw notFound(code);
    return i;
  }

  /// Applies a PATCH body the way the server would: merge JSON, re-parse.
  T patch<T>(
    T current,
    Json Function(T) toJson,
    Json changes,
    T Function(Json) fromJson,
  ) => fromJson({...toJson(current), ...changes});
}

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// [hour]:[minute] on the day [days] from today.
DateTime _at(int days, int hour, [int minute = 0]) =>
    DateTime(_today.year, _today.month, _today.day + days, hour, minute);

/// [hour]:[minute] on [weekday] (1 = Monday) of the current week.
DateTime _thisWeek(int weekday, int hour, [int minute = 0]) =>
    _at(weekday - _today.weekday, hour, minute);

final _user = User(
  id: 'mock-user-1',
  email: 'student@gmail.com',
  displayName: 'Nguyễn Văn A',
  dateOfBirth: DateTime(2005, 3, 12),
  timezone: 'Asia/Ho_Chi_Minh',
  googleCalendarConnected: true,
  createdAt: DateTime(2026, 9, 1),
  lastLoginAt: DateTime.now(),
);

const _tokens = AuthTokens(
  accessToken: 'mock-access-token',
  refreshToken: 'mock-refresh-token',
  expiresIn: 900,
);

List<SubjectDraft> _sampleSubjects() => [
  SubjectDraft(
    name: 'Cấu trúc dữ liệu',
    code: 'IT003',
    room: 'B1.02',
    lecturer: 'Nguyễn Văn B',
    dayOfWeek: 1,
    startTime: const ClockTime(7, 30),
    endTime: const ClockTime(9, 45),
    startDate: DateTime(2026, 9, 7),
    endDate: DateTime(2026, 12, 20),
    confidence: 0.87,
  ),
  SubjectDraft(
    name: 'Giải tích',
    code: 'MA003',
    room: 'A2.05',
    lecturer: 'Trần Thị C',
    dayOfWeek: 2,
    startTime: const ClockTime(9, 55),
    endTime: const ClockTime(12, 15),
    startDate: DateTime(2026, 9, 7),
    endDate: DateTime(2026, 12, 20),
    confidence: 0.93,
  ),
  SubjectDraft(
    name: 'Lap trinh huong doi tuong',
    code: 'IT002',
    room: 'C3.1l',
    dayOfWeek: 3,
    startTime: const ClockTime(13, 30),
    endTime: const ClockTime(15, 45),
    startDate: DateTime(2026, 9, 7),
    endDate: DateTime(2026, 12, 20),
    confidence: 0.48,
  ),
  SubjectDraft(
    name: 'Xác suất thống kê',
    code: 'MA004',
    room: 'A1.10',
    lecturer: 'Hoàng Văn F',
    dayOfWeek: 5,
    startTime: const ClockTime(13, 30),
    endTime: const ClockTime(15, 45),
    startDate: DateTime(2026, 9, 7),
    endDate: DateTime(2026, 12, 20),
    confidence: 0.91,
  ),
];

CalendarEvent _event(
  String id,
  String title,
  DateTime start,
  DateTime end, {
  EventSource source = EventSource.manual,
  String? location,
  String? subjectId,
  String? todoId,
  SyncStatus syncStatus = SyncStatus.synced,
}) => CalendarEvent(
  id: id,
  title: title,
  location: location,
  startAt: start,
  endAt: end,
  source: source,
  subjectId: subjectId,
  todoId: todoId,
  syncStatus: syncStatus,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
);

class MockAuthRepository extends _Mock implements AuthRepository {
  MockAuthRepository({Duration latency = Duration.zero}) : super(latency);

  @override
  Future<AuthSession> signInWithGoogle(String serverAuthCode) async {
    await delay();
    return AuthSession(tokens: _tokens, user: _user, isNewUser: false);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    await delay();
    return _tokens;
  }

  @override
  Future<void> logout() => delay();
}

class MockUserRepository extends _Mock implements UserRepository {
  MockUserRepository({Duration latency = Duration.zero}) : super(latency);

  User _me = _user;

  @override
  Future<User> getMe() async {
    await delay();
    return _me;
  }

  @override
  Future<User> updateMe(UserUpdate update) async {
    await delay();
    return _me = patch(_me, (u) => u.toJson(), update.toJson(), User.fromJson);
  }

  @override
  Future<void> deleteMe() => delay();
}

class MockSleepRepository extends _Mock implements SleepRepository {
  MockSleepRepository({Duration latency = Duration.zero}) : super(latency) {
    // Last 7 nights: (sleep hour, minute, wake hour, minute).
    const nights = [
      (23, 45, 6, 50),
      (0, 30, 7, 0),
      (23, 15, 7, 15),
      (1, 10, 6, 30),
      (23, 40, 7, 30),
      (0, 5, 8, 20),
      (23, 50, 6, 45),
    ];
    for (var i = 0; i < nights.length; i++) {
      final (sh, sm, wh, wm) = nights[i];
      final wakeDay = i - nights.length + 1;
      final sleepAt = _at(sh >= 12 ? wakeDay - 1 : wakeDay, sh, sm);
      final wakeAt = _at(wakeDay, wh, wm);
      _logs.add(_log(newId(), sleepAt, wakeAt, 3, null));
    }
  }

  final List<SleepLog> _logs = [];

  static const _profile = HealthProfile(
    chronotype: Chronotype.evening,
    usualSleepTime: ClockTime(23, 30),
    usualWakeTime: ClockTime(7, 0),
    sleepNeedHours: 8,
  );

  /// Alertness from 07:00 to 23:30, every 30 minutes.
  static const _alertness = [
    0.42,
    0.50,
    0.58,
    0.65,
    0.71,
    0.76,
    0.79,
    0.80,
    0.78,
    0.74,
    0.68,
    0.60,
    0.52,
    0.47,
    0.45,
    0.48,
    0.54,
    0.60,
    0.66,
    0.71,
    0.74,
    0.75,
    0.73,
    0.69,
    0.63,
    0.56,
    0.49,
    0.42,
    0.36,
    0.31,
    0.27,
    0.24,
    0.22,
    0.20,
  ];

  SleepLog _log(
    String id,
    DateTime sleepAt,
    DateTime wakeAt,
    int? quality,
    String? note,
  ) => SleepLog(
    id: id,
    sleepAt: sleepAt,
    wakeAt: wakeAt,
    durationMinutes: wakeAt.difference(sleepAt).inMinutes,
    quality: quality,
    note: note,
  );

  @override
  Future<HealthProfile?> getHealthProfile() async {
    await delay();
    return _profile;
  }

  @override
  Future<HealthProfile> saveHealthProfile(HealthProfile profile) async {
    await delay();
    return profile;
  }

  @override
  Future<Paginated<SleepLog>> listSleepLogs({
    DateTime? from,
    DateTime? to,
    int? limit,
    String? cursor,
  }) async {
    await delay();
    return Paginated(items: _logs.reversed.toList());
  }

  @override
  Future<SleepLog> createSleepLog(SleepLogCreate log) async {
    await delay();
    final created = _log(
      newId(),
      log.sleepAt,
      log.wakeAt,
      log.quality,
      log.note,
    );
    _logs.add(created);
    return created;
  }

  @override
  Future<SleepLog> updateSleepLog(String id, SleepLogUpdate update) async {
    await delay();
    final i = indexOf(_logs, (l) => l.id, id, 'SLEEP_LOG_NOT_FOUND');
    final merged = patch(
      _logs[i],
      (l) => l.toJson(),
      update.toJson(),
      SleepLog.fromJson,
    );
    return _logs[i] = _log(
      id,
      merged.sleepAt,
      merged.wakeAt,
      merged.quality,
      merged.note,
    );
  }

  @override
  Future<void> deleteSleepLog(String id) async {
    await delay();
    _logs.removeAt(indexOf(_logs, (l) => l.id, id, 'SLEEP_LOG_NOT_FOUND'));
  }

  @override
  Future<SleepDebt> getSleepDebt({int days = 7}) async {
    await delay();
    const slept = [425, 390, 480, 320, 470, 495, 415];
    final daily = [
      for (var i = 0; i < slept.length; i++)
        SleepDebtDay(
          date: _at(i - slept.length + 1, 0),
          sleptMinutes: slept[i],
          needMinutes: 480,
          debtMinutes: slept[i] >= 480 ? 0 : 480 - slept[i],
        ),
    ];
    return SleepDebt(
      days: daily.length,
      totalDebtMinutes: daily.fold(0, (sum, d) => sum + d.debtMinutes),
      daily: daily,
    );
  }

  @override
  Future<Biorhythm> getBiorhythm(DateTime date) async {
    await delay();
    DateTime t(int i) => DateTime(
      date.year,
      date.month,
      date.day,
      7,
    ).add(Duration(minutes: 30 * i));
    return Biorhythm(
      date: DateTime(date.year, date.month, date.day),
      intervalMinutes: 30,
      points: [
        for (var i = 0; i < _alertness.length; i++)
          BiorhythmPoint(
            time: t(i),
            processS: i / _alertness.length * 0.8,
            processC: _alertness[i],
            alertness: _alertness[i],
          ),
      ],
      peakWindows: [
        TimeWindow(start: t(4), end: t(9)),
        TimeWindow(start: t(19), end: t(22)),
      ],
      lowWindows: [TimeWindow(start: t(29), end: t(33))],
    );
  }
}

class MockTimetableRepository extends _Mock implements TimetableRepository {
  MockTimetableRepository({Duration latency = Duration.zero}) : super(latency) {
    for (final s in _sampleSubjects()) {
      _subjects.add(Subject.fromJson({...s.toJson(), 'id': newId()}));
    }
  }

  final List<Subject> _subjects = [];

  /// Any upload succeeds; a filename containing "fail" gives the
  /// `OCR_NO_TABLE_FOUND` result so the scan-failed screen can be built.
  final Map<String, bool> _jobFails = {};

  @override
  Future<OcrJob> uploadTimetablePhoto(
    Uint8List bytes, {
    required String filename,
  }) async {
    await delay();
    final id = newId();
    _jobFails[id] = filename.toLowerCase().contains('fail');
    return OcrJob(jobId: id, status: JobStatus.queued);
  }

  @override
  Future<OcrJob> getOcrJob(String jobId) async {
    await delay();
    final fails = _jobFails[jobId];
    if (fails == null) throw notFound('OCR_JOB_NOT_FOUND');
    return fails
        ? OcrJob(
            jobId: jobId,
            status: JobStatus.failed,
            error: 'OCR_NO_TABLE_FOUND',
          )
        : OcrJob(
            jobId: jobId,
            status: JobStatus.succeeded,
            subjects: _sampleSubjects(),
          );
  }

  @override
  Future<List<Subject>> listSubjects() async {
    await delay();
    return List.of(_subjects);
  }

  @override
  Future<List<Subject>> saveSubjects(
    List<SubjectDraft> subjects, {
    bool replaceExisting = false,
  }) async {
    await delay();
    if (replaceExisting) _subjects.clear();
    final saved = [
      for (final s in subjects)
        Subject.fromJson({...s.toJson(), 'id': newId()}),
    ];
    _subjects.addAll(saved);
    return saved;
  }

  @override
  Future<Subject> updateSubject(String id, SubjectUpdate update) async {
    await delay();
    final i = indexOf(_subjects, (s) => s.id, id, 'SUBJECT_NOT_FOUND');
    return _subjects[i] = patch(
      _subjects[i],
      (s) => s.toJson(),
      update.toJson(),
      Subject.fromJson,
    );
  }

  @override
  Future<void> deleteSubject(String id) async {
    await delay();
    _subjects.removeAt(
      indexOf(_subjects, (s) => s.id, id, 'SUBJECT_NOT_FOUND'),
    );
  }
}

class MockEventRepository extends _Mock implements EventRepository {
  MockEventRepository({Duration latency = Duration.zero}) : super(latency) {
    _events.addAll([
      _event(
        newId(),
        'Cấu trúc dữ liệu',
        _thisWeek(1, 7, 30),
        _thisWeek(1, 9, 45),
        source: EventSource.ocr,
        location: 'B1.02',
        subjectId: 'mock-subject-1',
      ),
      _event(
        newId(),
        'Giải tích',
        _thisWeek(2, 9, 55),
        _thisWeek(2, 12, 15),
        source: EventSource.ocr,
        location: 'A2.05',
        subjectId: 'mock-subject-2',
      ),
      _event(
        newId(),
        'Lập trình hướng đối tượng',
        _thisWeek(3, 13, 30),
        _thisWeek(3, 15, 45),
        source: EventSource.ocr,
        location: 'C3.11',
        subjectId: 'mock-subject-3',
      ),
      _event(
        newId(),
        'Xác suất thống kê',
        _thisWeek(5, 13, 30),
        _thisWeek(5, 15, 45),
        source: EventSource.ocr,
        location: 'A1.10',
        subjectId: 'mock-subject-4',
      ),
      _event(
        newId(),
        'Ôn bài tập lớn CTDL',
        _at(1, 19, 30),
        _at(1, 20, 20),
        source: EventSource.scheduler,
        todoId: 'mock-todo-1',
        syncStatus: SyncStatus.pending,
      ),
      _event(
        newId(),
        'Họp CLB Tin học',
        _thisWeek(6, 9),
        _thisWeek(6, 11),
        location: 'Hội trường E',
        syncStatus: SyncStatus.conflict,
      ),
    ]);
  }

  final List<CalendarEvent> _events = [];

  @override
  Future<List<CalendarEvent>> listEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    await delay();
    return _events
        .where((e) => e.startAt.isBefore(to) && e.endAt.isAfter(from))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  @override
  Future<CalendarEvent> createEvent(EventCreate event) async {
    await delay();
    final now = DateTime.now();
    final created = CalendarEvent.fromJson({
      ...event.toJson(),
      'id': newId(),
      'source': 'manual',
      'sync_status': 'not_synced',
      'created_at': formatDateTime(now),
      'updated_at': formatDateTime(now),
    });
    _events.add(created);
    return created;
  }

  @override
  Future<CalendarEvent> getEvent(String id) async {
    await delay();
    return _events[indexOf(_events, (e) => e.id, id, 'EVENT_NOT_FOUND')];
  }

  @override
  Future<CalendarEvent> updateEvent(String id, EventUpdate update) async {
    await delay();
    final i = indexOf(_events, (e) => e.id, id, 'EVENT_NOT_FOUND');
    return _events[i] = patch(
      _events[i],
      (e) => e.toJson(),
      update.toJson(),
      CalendarEvent.fromJson,
    );
  }

  @override
  Future<void> deleteEvent(String id) async {
    await delay();
    _events.removeAt(indexOf(_events, (e) => e.id, id, 'EVENT_NOT_FOUND'));
  }
}

class MockTodoRepository extends _Mock implements TodoRepository {
  MockTodoRepository({Duration latency = Duration.zero}) : super(latency) {
    Todo todo(
      String title,
      TodoCategory category,
      Priority priority, {
      String? description,
      DateTime? deadline,
      int? minutes,
      int? difficulty,
      TodoStatus status = TodoStatus.todo,
    }) => Todo(
      id: newId(),
      title: title,
      description: description,
      category: category,
      status: status,
      priority: priority,
      deadlineAt: deadline,
      estimatedMinutes: minutes,
      difficulty: difficulty,
      createdAt: _at(-3, 9),
      updatedAt: _at(-3, 9),
    );
    _todos.addAll([
      todo(
        'Bài tập lớn CTDL',
        TodoCategory.assignment,
        Priority.high,
        description: 'Chương 3–5',
        deadline: _at(6, 23, 59),
        minutes: 240,
        difficulty: 4,
      ),
      todo(
        'Ôn thi giữa kỳ Giải tích',
        TodoCategory.exam,
        Priority.high,
        deadline: _at(9, 23, 59),
        minutes: 300,
        difficulty: 5,
      ),
      todo(
        'Đọc slide OOP tuần 7',
        TodoCategory.study,
        Priority.medium,
        deadline: _at(2, 23, 59),
        minutes: 60,
        difficulty: 2,
        status: TodoStatus.inProgress,
      ),
      todo(
        'Nộp bài luận Anh văn',
        TodoCategory.assignment,
        Priority.medium,
        deadline: _at(4, 23, 59),
        minutes: 90,
        difficulty: 3,
      ),
      todo('Đi siêu thị', TodoCategory.personal, Priority.low),
      todo(
        'Đăng ký học phần học kỳ sau',
        TodoCategory.other,
        Priority.medium,
        deadline: _at(-1, 23, 59),
        status: TodoStatus.done,
      ),
    ]);
  }

  final List<Todo> _todos = [];

  @override
  Future<Paginated<Todo>> listTodos({
    TodoQuery query = const TodoQuery(),
    int? limit,
    String? cursor,
  }) async {
    await delay();
    final due = query.dueBefore;
    return Paginated(
      items: _todos
          .where((t) => query.status == null || t.status == query.status)
          .where((t) => query.category == null || t.category == query.category)
          .where((t) => due == null || (t.deadlineAt?.isBefore(due) ?? false))
          .toList(),
    );
  }

  @override
  Future<Todo> createTodo(TodoCreate todo) async {
    await delay();
    final now = formatDateTime(DateTime.now());
    final created = Todo.fromJson({
      ...todo.toJson(),
      'id': newId(),
      'created_at': now,
      'updated_at': now,
    });
    _todos.add(created);
    return created;
  }

  @override
  Future<Todo> getTodo(String id) async {
    await delay();
    return _todos[indexOf(_todos, (t) => t.id, id, 'TODO_NOT_FOUND')];
  }

  @override
  Future<Todo> updateTodo(String id, TodoUpdate update) async {
    await delay();
    final i = indexOf(_todos, (t) => t.id, id, 'TODO_NOT_FOUND');
    return _todos[i] = patch(_todos[i], (t) => t.toJson(), {
      ...update.toJson(),
      'updated_at': formatDateTime(DateTime.now()),
    }, Todo.fromJson);
  }

  @override
  Future<void> deleteTodo(String id) async {
    await delay();
    _todos.removeAt(indexOf(_todos, (t) => t.id, id, 'TODO_NOT_FOUND'));
  }
}

class MockVoiceRepository extends _Mock implements VoiceRepository {
  MockVoiceRepository({Duration latency = Duration.zero}) : super(latency);

  @override
  Future<VoiceTranscription> transcribe(
    Uint8List audio, {
    required String filename,
  }) async {
    await delay();
    return VoiceTranscription(
      transcript: 'Thứ sáu nộp bài tập lớn cấu trúc dữ liệu',
      todoDraft: TodoDraft(
        title: 'Nộp bài tập lớn cấu trúc dữ liệu',
        category: TodoCategory.assignment,
        deadlineAt: _thisWeek(5, 23, 59),
        priority: Priority.medium,
      ),
    );
  }
}

class MockScheduleRepository extends _Mock implements ScheduleRepository {
  MockScheduleRepository({Duration latency = Duration.zero}) : super(latency);

  static final _blocks = [
    StudyBlock(
      todoId: 'mock-todo-1',
      title: 'Bài tập lớn CTDL',
      startAt: _at(1, 9, 30),
      endAt: _at(1, 10, 20),
      alertness: 0.82,
    ),
    StudyBlock(
      todoId: 'mock-todo-2',
      title: 'Ôn thi giữa kỳ Giải tích',
      startAt: _at(1, 19, 30),
      endAt: _at(1, 20, 20),
      alertness: 0.74,
    ),
    StudyBlock(
      todoId: 'mock-todo-1',
      title: 'Bài tập lớn CTDL',
      startAt: _at(2, 10, 0),
      endAt: _at(2, 10, 50),
      alertness: 0.79,
    ),
  ];

  @override
  Future<ScheduleSuggestion> generate(ScheduleRequest request) async {
    await delay();
    return ScheduleSuggestion(
      suggestionId: 'mock-suggestion-1',
      blocks: _blocks,
      unscheduled: const [
        UnscheduledTodo(
          todoId: 'mock-todo-5',
          reason: 'NOT_ENOUGH_TIME_BEFORE_DEADLINE',
        ),
      ],
      solverStatus: 'FEASIBLE',
    );
  }

  @override
  Future<List<CalendarEvent>> apply(
    String suggestionId, {
    List<int>? blockIndexes,
    bool syncToGoogle = false,
  }) async {
    await delay();
    final indexes = blockIndexes ?? List.generate(_blocks.length, (i) => i);
    return [
      for (final i in indexes)
        _event(
          newId(),
          _blocks[i].title,
          _blocks[i].startAt,
          _blocks[i].endAt,
          source: EventSource.scheduler,
          todoId: _blocks[i].todoId,
          syncStatus: syncToGoogle ? SyncStatus.synced : SyncStatus.notSynced,
        ),
    ];
  }
}

class MockCalendarSyncRepository extends _Mock
    implements CalendarSyncRepository {
  MockCalendarSyncRepository({Duration latency = Duration.zero})
    : super(latency);

  @override
  Future<CalendarStatus> getStatus() async {
    await delay();
    return CalendarStatus(
      connected: true,
      calendarId: 'primary',
      twoWaySync: true,
      lastSyncedAt: DateTime.now().subtract(const Duration(hours: 3)),
      pendingCount: 1,
      conflictCount: 1,
    );
  }

  @override
  Future<SyncResult> sync() async {
    await delay();
    return const SyncResult(pushed: 1, failed: 0, conflicts: 1);
  }

  @override
  Future<List<SyncConflict>> listConflicts() async {
    await delay();
    final local = _event(
      'mock-event-club',
      'Họp CLB Tin học',
      _thisWeek(6, 9),
      _thisWeek(6, 11),
      location: 'Hội trường E',
      syncStatus: SyncStatus.conflict,
    );
    return [
      SyncConflict(
        id: 'mock-conflict-1',
        eventId: local.id,
        local: local,
        google: GoogleEventSnapshot(
          title: 'Họp CLB Tin học (dời giờ)',
          startAt: _thisWeek(6, 10),
          endAt: _thisWeek(6, 12),
        ),
        detectedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ];
  }

  @override
  Future<CalendarEvent> resolveConflict(
    String id,
    ConflictResolution keep,
  ) async {
    final conflict = (await listConflicts()).firstWhere(
      (c) => c.id == id,
      orElse: () => throw notFound('CONFLICT_NOT_FOUND'),
    );
    final g = conflict.google;
    return CalendarEvent.fromJson({
      ...conflict.local.toJson(),
      if (keep == ConflictResolution.google) ...{
        'title': g.title,
        'start_at': formatDateTime(g.startAt),
        'end_at': formatDateTime(g.endAt),
      },
      'sync_status': 'synced',
    });
  }
}

class MockReminderRepository extends _Mock implements ReminderRepository {
  MockReminderRepository({Duration latency = Duration.zero}) : super(latency);

  ReminderSettings _settings = const ReminderSettings(
    bedtimeReminderEnabled: true,
    bedtimeReminderMinutesBefore: 30,
    deadlineReminderEnabled: true,
    deadlineReminderHoursBefore: [24, 2],
    motivationEnabled: true,
    quietHours: QuietHours(start: ClockTime(23, 0), end: ClockTime(7, 0)),
  );

  @override
  Future<ReminderSettings> getSettings() async {
    await delay();
    return _settings;
  }

  @override
  Future<ReminderSettings> saveSettings(ReminderSettings settings) async {
    await delay();
    return _settings = settings;
  }

  @override
  Future<void> registerDevice(String fcmToken, {String platform = 'android'}) =>
      delay();

  @override
  Future<void> unregisterDevice(String fcmToken) => delay();

  @override
  Future<Quote> randomQuote({
    QuoteContext context = QuoteContext.general,
  }) async {
    await delay();
    return const Quote(
      text: 'Mỗi ngày tiến một chút là đủ rồi.',
      source: QuoteSource.fallback,
    );
  }
}
