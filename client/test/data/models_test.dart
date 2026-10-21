import 'package:client/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Examples copied from docs/api-v1.md.
void main() {
  group('DTOs parse the api-v1 examples', () {
    test('AuthSession', () {
      final session = AuthSession.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'token_type': 'bearer',
        'expires_in': 900,
        'user': _userJson,
        'is_new_user': true,
      });
      expect(session.tokens.accessToken, 'a');
      expect(session.isNewUser, isTrue);
      expect(session.user.displayName, 'Nguyen Van A');
    });

    test('User keeps the instant and date of birth', () {
      final user = User.fromJson(_userJson);
      expect(user.dateOfBirth, DateTime(2005, 3, 12));
      expect(user.createdAt.toUtc(), DateTime.utc(2026, 10, 19, 1));
      expect(User.fromJson(user.toJson()).toJson(), user.toJson());
    });

    test('HealthProfile', () {
      final p = HealthProfile.fromJson({
        'chronotype': 'evening',
        'usual_sleep_time': '23:30',
        'usual_wake_time': '07:00',
        'sleep_need_hours': 8,
      });
      expect(p.chronotype, Chronotype.evening);
      expect(p.usualSleepTime, const ClockTime(23, 30));
      expect(p.sleepNeedHours, 8.0);
      expect(p.toJson()['usual_wake_time'], '07:00');
    });

    test('SleepLog, SleepDebt, Biorhythm', () {
      final log = SleepLog.fromJson({
        'id': 'x',
        'sleep_at': '2026-10-18T23:45:00+07:00',
        'wake_at': '2026-10-19T06:50:00+07:00',
        'duration_minutes': 425,
        'quality': 3,
        'note': null,
      });
      expect(log.wakeAt.difference(log.sleepAt).inMinutes, 425);

      final debt = SleepDebt.fromJson({
        'days': 7,
        'total_debt_minutes': 310,
        'daily': [
          {
            'date': '2026-10-13',
            'slept_minutes': 400,
            'need_minutes': 480,
            'debt_minutes': 80,
          },
        ],
      });
      expect(debt.daily.single.date, DateTime(2026, 10, 13));

      final bio = Biorhythm.fromJson({
        'date': '2026-10-19',
        'interval_minutes': 30,
        'points': [
          {
            'time': '2026-10-19T08:00:00+07:00',
            'process_s': 0.32,
            'process_c': 0.61,
            'alertness': 0.71,
          },
        ],
        'peak_windows': [
          {
            'start': '2026-10-19T09:30:00+07:00',
            'end': '2026-10-19T11:30:00+07:00',
          },
        ],
        'low_windows': [],
      });
      expect(bio.points.single.alertness, 0.71);
      expect(
        bio.peakWindows.single.end.difference(bio.peakWindows.single.start),
        const Duration(hours: 2),
      );
    });

    test('OcrJob succeeded and failed', () {
      final job = OcrJob.fromJson({
        'job_id': 'j',
        'status': 'succeeded',
        'error': null,
        'result': {
          'subjects': [
            {
              'name': 'Cấu trúc dữ liệu',
              'code': 'IT003',
              'room': 'B1.02',
              'lecturer': 'Nguyen Van B',
              'day_of_week': 1,
              'start_time': '07:30',
              'end_time': '09:45',
              'start_date': '2026-09-07',
              'end_date': '2026-12-20',
              'confidence': 0.87,
            },
          ],
        },
      });
      final s = job.subjects.single;
      expect(s.startTime, const ClockTime(7, 30));
      expect(s.confidence, 0.87);
      expect(
        s.toJson().containsKey('confidence'),
        isFalse,
        reason: 'T4 body has no confidence',
      );

      final failed = OcrJob.fromJson({
        'job_id': 'j',
        'status': 'failed',
        'error': 'OCR_NO_TABLE_FOUND',
        'result': null,
      });
      expect(failed.status.isFinished, isTrue);
      expect(failed.subjects, isEmpty);
    });

    test('CalendarEvent', () {
      final e = CalendarEvent.fromJson({
        'id': 'e',
        'title': 'Ôn thi Giải tích',
        'description': null,
        'location': null,
        'start_at': '2026-10-20T09:30:00+07:00',
        'end_at': '2026-10-20T11:00:00+07:00',
        'all_day': false,
        'rrule': null,
        'source': 'scheduler',
        'subject_id': null,
        'todo_id': 't',
        'google_event_id': 'abc123',
        'sync_status': 'synced',
        'created_at': '2026-10-19T08:00:00+07:00',
        'updated_at': '2026-10-19T08:00:00+07:00',
      });
      expect(e.source, EventSource.scheduler);
      expect(e.syncStatus, SyncStatus.synced);
      expect(CalendarEvent.fromJson(e.toJson()).toJson(), e.toJson());
    });

    test('Todo and VoiceTranscription', () {
      final todo = Todo.fromJson({
        'id': 't',
        'title': 'Bài tập lớn CTDL',
        'description': 'Chương 3–5',
        'category': 'assignment',
        'status': 'in_progress',
        'priority': 'high',
        'deadline_at': '2026-10-25T23:59:00+07:00',
        'estimated_minutes': 240,
        'difficulty': 4,
        'start_at': null,
        'end_at': null,
        'created_at': '2026-10-19T08:00:00+07:00',
        'updated_at': '2026-10-19T08:00:00+07:00',
      });
      expect(todo.status, TodoStatus.inProgress);

      final voice = VoiceTranscription.fromJson({
        'transcript': 'Thứ sáu nộp bài tập lớn cấu trúc dữ liệu',
        'todo_draft': {
          'title': 'Nộp bài tập lớn cấu trúc dữ liệu',
          'category': 'assignment',
          'deadline_at': '2026-10-23T23:59:00+07:00',
          'estimated_minutes': null,
          'priority': 'medium',
        },
      });
      expect(voice.todoDraft!.category, TodoCategory.assignment);
      expect(voice.todoDraft!.estimatedMinutes, isNull);
    });

    test('ScheduleSuggestion', () {
      final s = ScheduleSuggestion.fromJson({
        'suggestion_id': 's',
        'blocks': [
          {
            'todo_id': 't',
            'title': 'Bài tập lớn CTDL',
            'start_at': '2026-10-21T09:30:00+07:00',
            'end_at': '2026-10-21T10:20:00+07:00',
            'alertness': 0.82,
          },
        ],
        'unscheduled': [
          {'todo_id': 'u', 'reason': 'NOT_ENOUGH_TIME_BEFORE_DEADLINE'},
        ],
        'solver_status': 'OPTIMAL',
      });
      expect(s.blocks.single.alertness, 0.82);
      expect(s.unscheduled.single.reason, 'NOT_ENOUGH_TIME_BEFORE_DEADLINE');
    });

    test('Calendar status, reminder settings, quote', () {
      final status = CalendarStatus.fromJson({
        'connected': true,
        'calendar_id': 'primary',
        'two_way_sync': true,
        'last_synced_at': '2026-10-19T08:00:00+07:00',
        'pending_count': 2,
        'conflict_count': 0,
      });
      expect(status.pendingCount, 2);

      final settings = ReminderSettings.fromJson({
        'bedtime_reminder_enabled': true,
        'bedtime_reminder_minutes_before': 30,
        'deadline_reminder_enabled': true,
        'deadline_reminder_hours_before': [24, 2],
        'motivation_enabled': true,
        'quiet_hours': {'start': '23:00', 'end': '07:00'},
      });
      expect(settings.deadlineReminderHoursBefore, [24, 2]);
      expect(settings.quietHours!.start, const ClockTime(23, 0));

      final quote = Quote.fromJson({
        'text': '...',
        'author': null,
        'source': 'fallback',
      });
      expect(quote.source, QuoteSource.fallback);
    });
  });

  group('PATCH bodies', () {
    test('omit unset fields and send explicit nulls', () {
      expect(const TodoUpdate(status: TodoStatus.done).toJson(), {
        'status': 'done',
      });
      expect(
        const TodoUpdate(
          description: Nullable(null),
          estimatedMinutes: Nullable(30),
        ).toJson(),
        {'description': null, 'estimated_minutes': 30},
      );
      expect(
        TodoUpdate(deadlineAt: Nullable(DateTime.utc(2026, 10, 25, 16, 59)))
            .toJson(),
        {'deadline_at': '2026-10-25T16:59:00.000Z'},
      );
      expect(const UserUpdate(dateOfBirth: Nullable(null)).toJson(), {
        'date_of_birth': null,
      });
      expect(
        const SubjectUpdate(
          room: Nullable('B1.03'),
          startTime: ClockTime(8, 0),
        ).toJson(),
        {'start_time': '08:00', 'room': 'B1.03'},
      );
      expect(const EventUpdate().toJson(), isEmpty);
    });
  });

  group('helpers', () {
    test('enums reject unknown values', () {
      expect(() => TodoStatus.fromJson('archived'), throwsFormatException);
      expect(TodoStatus.inProgress.toJson(), 'in_progress');
      expect(SyncStatus.fromJson('not_synced'), SyncStatus.notSynced);
    });

    test('ClockTime', () {
      expect(ClockTime.parse('07:05').toJson(), '07:05');
      expect(
        ClockTime.parse('23:30').compareTo(const ClockTime(7, 0)),
        greaterThan(0),
      );
      expect(
        const ClockTime(9, 30).on(DateTime(2026, 10, 19)),
        DateTime(2026, 10, 19, 9, 30),
      );
      expect(() => ClockTime.parse('7'), throwsFormatException);
    });

    test('date formatting', () {
      expect(formatDate(DateTime(2026, 1, 5, 23)), '2026-01-05');
      expect(parseDate('2026-10-19'), DateTime(2026, 10, 19));
    });

    test('list bodies may be bare arrays or wrapped in items', () {
      Json row(String id) => {'id': id};
      expect(parseItems([row('a')], (j) => j['id']), ['a']);
      expect(
        parseItems({
          'items': [row('b')],
        }, (j) => j['id']),
        ['b'],
      );
      final page = Paginated.fromJson({
        'items': [row('c')],
        'next_cursor': 'n',
      }, (j) => j['id']);
      expect(page.hasMore, isTrue);
    });
  });
}

const _userJson = {
  'id': 'u',
  'email': 'student@gmail.com',
  'display_name': 'Nguyen Van A',
  'avatar_url': 'https://example.com/a.png',
  'date_of_birth': '2005-03-12',
  'timezone': 'Asia/Ho_Chi_Minh',
  'google_calendar_connected': true,
  'created_at': '2026-10-19T08:00:00+07:00',
  'last_login_at': '2026-10-19T08:00:00+07:00',
};
