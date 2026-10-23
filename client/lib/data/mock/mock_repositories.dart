import 'dart:typed_data';

import '../api/api_exception.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/calendar_sync_repository.dart';
import '../repositories/event_repository.dart';
import '../repositories/home_repository.dart';
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
  onboardingCompleted: true,
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
  EventKind kind = EventKind.other,
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
  kind: kind,
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

const _model = ModelSummary(
  phiHours: 18.4,
  phiSdHours: 1.0,
  chiWHours: 18.2,
  chiWSdHours: 2.5,
  personalizationLevel: PersonalizationLevel.priorOnly,
  kssDays: 0,
);

const _mctq = MctqAnswers(
  sleepOnsetWork: ClockTime(0, 30),
  sleepEndWork: ClockTime(6, 30),
  sleepOnsetFree: ClockTime(1, 45),
  sleepEndFree: ClockTime(10, 0),
  workDays: 5,
);

/// Predicted KSS from 07:00 to 23:30, every 30 minutes (lower = more alert).
const _kss = [
  6.0, 5.4, 4.8, 4.3, 3.9, 3.6, 3.4, 3.3, 3.5, 3.8, 4.2, 4.8, 5.3, 5.6, //
  5.7, 5.5, 5.0, 4.6, 4.2, 3.9, 3.7, 3.6, 3.8, 4.1, 4.6, 5.1, 5.6, 6.1, //
  6.5, 6.9, 7.2, 7.5, 7.7, 7.9,
];

int _score(double kss) => (100 * (9 - kss) / 8).round().clamp(0, 100);

ProjectedSleep _tonight(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return ProjectedSleep(
    nightOf: d,
    naturalSleepAt: DateTime(d.year, d.month, d.day + 1, 1, 45),
    naturalWakeAt: DateTime(d.year, d.month, d.day + 1, 8, 24),
    requiredWakeAt: DateTime(d.year, d.month, d.day + 1, 6, 30),
    recommendedSleepAt: DateTime(d.year, d.month, d.day, 22, 30),
    projectedSleepMinutes: 480,
  );
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

  HealthProfile _profile = HealthProfile(
    chronotype: Chronotype.bear,
    spectrum: ChronotypeSpectrum.intermediate,
    sleepConcern: SleepConcern.none,
    chronotypeSource: ChronotypeSource.mctq,
    usualSleepTime: const ClockTime(0, 30),
    usualWakeTime: const ClockTime(6, 30),
    sleepNeedHours: 8,
    morningPrepMinutes: 60,
    mctq: _mctq,
    regularSchedule: true,
    screenTrackingEnabled: false,
    updatedAt: DateTime(2026, 9, 1),
  );

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
    createdAt: wakeAt,
    updatedAt: wakeAt,
  );

  @override
  Future<ChronotypeAssessment> assessChronotype(
    ChronotypeAssessmentRequest request,
  ) async {
    await delay();
    final shift = request.schoolOnsetShiftMinutes ?? 0;
    return ChronotypeAssessment(
      chronotype: Chronotype.bear,
      spectrum: ChronotypeSpectrum.intermediate,
      sleepConcern: SleepConcern.none,
      source: ChronotypeSource.mctq,
      phiPriorHours: 18.39,
      phiPriorSdHours: 1.0,
      naturalSleepTime: const ClockTime(1, 45),
      naturalWakeTime: const ClockTime(8, 24),
      sleepShortfallHours: 0.36,
      typicalWeek: TypicalWeek(
        phiHours: 18.39,
        schoolOnsetShiftMinutes: shift,
        days: [
          for (var day = 0; day < 7; day++)
            TypicalWeekDay(
              day: day,
              wakeTime: day < 5
                  ? const ClockTime(6, 30)
                  : const ClockTime(10, 0),
              sleepTime: day < 4 || day == 6
                  ? const ClockTime(0, 30)
                  : const ClockTime(1, 45),
              kss08: day < 5 ? 4.3 : null,
              kss14: 4.9,
              kss22: 6.5,
              worstTime: const ClockTime(0, 25),
              worstKss: 7.6,
              minutesPastThreshold: day < 5 ? 15 : 0,
              peakStart: const ClockTime(9, 30),
              peakMeanKss: 3.6,
            ),
        ],
        points: [
          for (var i = 0; i < _kss.length; i++)
            TypicalWeekPoint(
              day: 0,
              time: ClockTime(7 + i ~/ 2, i.isEven ? 0 : 30),
              asleep: false,
              alertness: (7.5 - _kss[i]) / 9,
              kss: _kss[i],
            ),
        ],
      ),
    );
  }

  @override
  Future<HealthProfile?> getHealthProfile() async {
    await delay();
    return _profile;
  }

  @override
  Future<HealthProfile> saveHealthProfile(HealthProfileInput profile) async {
    await delay();
    return _profile = HealthProfile.fromJson({
      ..._profile.toJson(),
      ...profile.toJson(),
      'chronotype': profile.chronotype?.value ?? _profile.chronotype.value,
      'updated_at': formatDateTime(DateTime.now()),
    });
  }

  @override
  Future<List<SleepLog>> listSleepLogs({
    DateTime? from,
    DateTime? to,
    SleepSource? source,
    bool? confirmed,
  }) async {
    await delay();
    return _logs.reversed
        .where((l) => source == null || l.source == source)
        .where((l) => confirmed == null || l.confirmed == confirmed)
        .toList();
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
          hasData: true,
          sleptMinutes: slept[i],
          needMinutes: 480,
          debtMinutes: 480 - slept[i],
          midSleep: const ClockTime(3, 30),
          isFreeDay: _at(i - slept.length + 1, 0).weekday > 5,
        ),
    ];
    final total = daily.fold(0, (sum, d) => sum + d.debtMinutes);
    return SleepDebt(
      days: daily.length,
      totalDebtMinutes: total < 0 ? 0 : total,
      averageSleepMinutes: slept.reduce((a, b) => a + b) ~/ slept.length,
      socialJetlagHours: 1.9,
      currentProcessS: 0.52,
      daily: daily,
    );
  }

  @override
  Future<Biorhythm> getBiorhythm({
    DateTime? date,
    int? days,
    int? intervalMinutes,
  }) async {
    await delay();
    final day = date ?? _today;
    DateTime t(int i) => DateTime(
      day.year,
      day.month,
      day.day,
      7,
    ).add(Duration(minutes: 30 * i));
    BiorhythmWindow window(int from, int to) => BiorhythmWindow(
      start: t(from),
      end: t(to),
      meanKssPred: _kss[from],
      alertnessScore: _score(_kss[from]),
    );
    return Biorhythm(
      date: DateTime(day.year, day.month, day.day),
      days: 1,
      intervalMinutes: 30,
      timezone: 'Asia/Ho_Chi_Minh',
      model: _model,
      points: [
        for (var i = 0; i < _kss.length; i++)
          BiorhythmPoint(
            time: t(i),
            asleep: false,
            sleepState: SleepState.typical,
            processS: 0.2 + i / _kss.length * 0.6,
            processC: (4.5 - _kss[i]) / 3.5,
            upperThreshold: 0.79,
            lowerThreshold: 0.29,
            alertness: (7.5 - _kss[i]) / 9,
            kssPred: _kss[i],
            kssLo: _kss[i] - 1.5,
            kssHi: _kss[i] + 1.5,
            alertnessScore: _score(_kss[i]),
          ),
      ],
      peakWindows: [window(5, 9), window(19, 23)],
      lowWindows: [window(29, 33)],
      projectedSleep: [_tonight(day)],
      warnings: const ['TYPICAL_WEEK'],
    );
  }
}

class MockTimetableRepository extends _Mock implements TimetableRepository {
  MockTimetableRepository({Duration latency = Duration.zero}) : super(latency) {
    for (final s in _sampleSubjects()) {
      _subjects.add(_saved(s));
    }
  }

  final List<Subject> _subjects = [];

  Subject _saved(SubjectDraft s) => Subject.fromJson({
    ...s.toJson(),
    'id': newId(),
    'created_at': formatDateTime(DateTime(2026, 9, 1)),
    'updated_at': formatDateTime(DateTime(2026, 9, 1)),
  });

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
    final saved = [for (final s in subjects) _saved(s)];
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
        kind: EventKind.classSession,
        location: 'B1.02',
        subjectId: 'mock-subject-1',
      ),
      _event(
        newId(),
        'Giải tích',
        _thisWeek(2, 9, 55),
        _thisWeek(2, 12, 15),
        source: EventSource.ocr,
        kind: EventKind.classSession,
        location: 'A2.05',
        subjectId: 'mock-subject-2',
      ),
      _event(
        newId(),
        'Lập trình hướng đối tượng',
        _thisWeek(3, 13, 30),
        _thisWeek(3, 15, 45),
        source: EventSource.ocr,
        kind: EventKind.classSession,
        location: 'C3.11',
        subjectId: 'mock-subject-3',
      ),
      _event(
        newId(),
        'Xác suất thống kê',
        _thisWeek(5, 13, 30),
        _thisWeek(5, 15, 45),
        source: EventSource.ocr,
        kind: EventKind.classSession,
        location: 'A1.10',
        subjectId: 'mock-subject-4',
      ),
      _event(
        newId(),
        'Ôn bài tập lớn CTDL',
        _at(1, 19, 30),
        _at(1, 20, 20),
        source: EventSource.scheduler,
        kind: EventKind.study,
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
    EventKind? kind,
    EventSource? source,
  }) async {
    await delay();
    return _events
        .where((e) => e.startAt.isBefore(to) && e.endAt.isAfter(from))
        .where((e) => kind == null || e.kind == kind)
        .where((e) => source == null || e.source == source)
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
    final before = query.dueBefore;
    final after = query.dueAfter;
    return Paginated(
      items: _todos
          .where(
            (t) => query.statuses.isEmpty || query.statuses.contains(t.status),
          )
          .where((t) => query.category == null || t.category == query.category)
          .where(
            (t) => before == null || (t.deadlineAt?.isBefore(before) ?? false),
          )
          .where(
            (t) => after == null || (t.deadlineAt?.isAfter(after) ?? false),
          )
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
      'status': TodoStatus.todo.value,
      'scheduled_minutes': 0,
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
    final now = formatDateTime(DateTime.now());
    final status = update.status;
    return _todos[i] = patch(_todos[i], (t) => t.toJson(), {
      ...update.toJson(),
      if (status != null)
        'completed_at': status == TodoStatus.done ? now : null,
      'updated_at': now,
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
    DateTime? referenceTime,
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
      parser: 'gemini',
    );
  }
}

class MockScheduleRepository extends _Mock implements ScheduleRepository {
  MockScheduleRepository({Duration latency = Duration.zero}) : super(latency);

  static final _blocks = [
    ScheduleBlock(
      index: 0,
      kind: EventKind.study,
      todoId: 'mock-todo-1',
      title: 'Bài tập lớn CTDL',
      startAt: _at(1, 9, 30),
      endAt: _at(1, 11, 0),
      predictedKss: 3.4,
      alertnessScore: 70,
    ),
    ScheduleBlock(
      index: 1,
      kind: EventKind.study,
      todoId: 'mock-todo-2',
      title: 'Ôn thi giữa kỳ Giải tích',
      startAt: _at(1, 16, 30),
      endAt: _at(1, 18, 0),
      predictedKss: 3.7,
      alertnessScore: 66,
    ),
    ScheduleBlock(
      index: 2,
      kind: EventKind.bedtime,
      title: 'Đi ngủ',
      startAt: _at(1, 22, 30),
      endAt: _at(2, 6, 30),
    ),
  ];

  @override
  Future<ScheduleSuggestion> generate(ScheduleRequest request) async {
    await delay();
    return ScheduleSuggestion(
      suggestionId: 'mock-suggestion-1',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      from: request.from,
      to: request.to,
      solverStatus: 'FEASIBLE',
      blocks: _blocks,
      unscheduled: const [
        UnscheduledTodo(
          todoId: 'mock-todo-5',
          reason: 'NOT_ENOUGH_TIME_BEFORE_DEADLINE',
          missingMinutes: 60,
        ),
      ],
      stats: const ScheduleStats(
        studyMinutes: 180,
        meanPredictedKss: 3.55,
        goldenHourRatio: 0.83,
        solveMs: 140,
      ),
      model: _model,
    );
  }

  @override
  Future<ScheduleApplyResult> apply(
    String suggestionId, {
    List<int>? blockIndexes,
    bool syncToGoogle = false,
  }) async {
    await delay();
    final indexes = blockIndexes ?? List.generate(_blocks.length, (i) => i);
    return ScheduleApplyResult(
      events: [
        for (final i in indexes)
          _event(
            newId(),
            _blocks[i].title,
            _blocks[i].startAt,
            _blocks[i].endAt,
            source: EventSource.scheduler,
            kind: _blocks[i].kind,
            todoId: _blocks[i].todoId,
            syncStatus: syncToGoogle ? SyncStatus.synced : SyncStatus.notSynced,
          ),
      ],
      sync: syncToGoogle
          ? SyncResult(
              pushed: indexes.length,
              pulled: 0,
              failed: 0,
              conflicts: 0,
            )
          : null,
    );
  }
}

class MockCalendarSyncRepository extends _Mock
    implements CalendarSyncRepository {
  MockCalendarSyncRepository({Duration latency = Duration.zero})
    : super(latency);

  late CalendarStatus _status = CalendarStatus(
    connected: true,
    googleEmail: _user.email,
    calendarId: 'primary',
    twoWaySync: true,
    lastSyncedAt: DateTime.now().subtract(const Duration(hours: 3)),
    pendingCount: 1,
    conflictCount: 1,
  );

  @override
  Future<CalendarStatus> getStatus() async {
    await delay();
    return _status;
  }

  @override
  Future<CalendarStatus> connect(String serverAuthCode) async {
    await delay();
    return _status = CalendarStatus.fromJson({
      ..._status.toJson(),
      'connected': true,
      'google_email': _user.email,
      'calendar_id': 'primary',
    });
  }

  @override
  Future<void> disconnect() async {
    await delay();
    _status = CalendarStatus.fromJson({
      ..._status.toJson(),
      'connected': false,
      'google_email': null,
      'calendar_id': null,
    });
  }

  @override
  Future<CalendarStatus> updateSettings({
    String? calendarId,
    bool? twoWaySync,
  }) async {
    await delay();
    return _status = CalendarStatus.fromJson({
      ..._status.toJson(),
      'calendar_id': ?calendarId,
      'two_way_sync': ?twoWaySync,
    });
  }

  @override
  Future<SyncResult> sync({List<String>? eventIds}) async {
    await delay();
    return const SyncResult(pushed: 1, pulled: 0, failed: 0, conflicts: 1);
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
          location: 'Hội trường E',
          startAt: _thisWeek(6, 10),
          endAt: _thisWeek(6, 12),
          updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
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
    kssPromptEnabled: true,
    kssPromptsPerDay: 4,
    kssPromptWindow: ClockWindow(start: ClockTime(8, 0), end: ClockTime(23, 0)),
    sleepConfirmEnabled: true,
    motivationEnabled: true,
    quietHours: ClockWindow(start: ClockTime(23, 0), end: ClockTime(7, 0)),
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
  Future<void> registerDevice(
    String fcmToken, {
    DevicePlatform platform = DevicePlatform.android,
  }) => delay();

  @override
  Future<void> unregisterDevice(String fcmToken) => delay();

  @override
  Future<Quote> randomQuote({
    QuoteContext context = QuoteContext.general,
  }) async {
    await delay();
    return Quote(
      text: 'Mỗi ngày tiến một chút là đủ rồi.',
      source: QuoteSource.fallback,
      context: context,
    );
  }
}

class MockHomeRepository extends _Mock implements HomeRepository {
  MockHomeRepository({Duration latency = Duration.zero}) : super(latency);

  final _sleep = MockSleepRepository();
  final _events = MockEventRepository();
  final _todos = MockTodoRepository();

  @override
  Future<HomeOverview> getOverview() async {
    await delay();
    final bio = await _sleep.getBiorhythm();
    final now = DateTime.now();
    final point = bio.points.lastWhere(
      (p) => !p.time.isAfter(now),
      orElse: () => bio.points.first,
    );
    final todos =
        (await _todos.listTodos(
            query: const TodoQuery(
              statuses: [TodoStatus.todo, TodoStatus.inProgress],
            ),
          )).items.where((t) => t.deadlineAt != null).toList()
          ..sort((a, b) => a.deadlineAt!.compareTo(b.deadlineAt!));
    return HomeOverview(
      date: _today,
      now: NowState(
        time: now,
        asleep: point.asleep,
        processS: point.processS,
        processC: point.processC,
        kssPred: point.kssPred,
        kssLo: point.kssLo,
        kssHi: point.kssHi,
        alertnessScore: point.alertnessScore,
      ),
      nextPeakWindow: bio.peakWindows
          .where((w) => w.end.isAfter(now))
          .firstOrNull,
      tonight: bio.projectedSleep.first,
      todayEvents: await _events.listEvents(from: _today, to: _at(1, 0)),
      upcomingTodos: todos.take(3).toList(),
      sleepDebt7dMinutes: (await _sleep.getSleepDebt()).totalDebtMinutes,
      lastNight: (await _sleep.listSleepLogs()).first,
      needsSleepConfirmation: false,
      kssCheckinDue: false,
      model: _model,
    );
  }
}
