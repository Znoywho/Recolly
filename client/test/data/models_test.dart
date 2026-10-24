import 'package:client/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Examples copied from docs/openapi.yaml (draft 2.1).
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
        'chronotype': 'bear',
        'spectrum': 'intermediate',
        'sleep_concern': 'none',
        'chronotype_source': 'mctq',
        'usual_sleep_time': '23:30',
        'usual_wake_time': '07:00',
        'sleep_need_hours': 8,
        'morning_prep_minutes': 60,
        'mctq': {
          'sleep_onset_work': '00:30',
          'sleep_end_work': '06:30',
          'sleep_onset_free': '01:45',
          'sleep_end_free': '10:00',
          'work_days': 5,
        },
        'mctq_result': _mctqResultJson,
        'rmeq_score': null,
        'rmeq_category': null,
        'regular_schedule': true,
        'sleep_quality': {
          'slow_onset_nights': '1-2',
          'night_waking_nights': '0',
          'duration': null,
        },
        'screen_tracking_enabled': true,
        'updated_at': '2026-10-19T08:00:00+07:00',
      });
      expect(p.chronotype, Chronotype.bear);
      expect(p.usualSleepTime, const ClockTime(23, 30));
      expect(p.sleepNeedHours, 8.0);
      expect(p.mctq!.alarmOnFreeDays, isFalse);
      expect(p.mctqResult!.msfSc, const ClockTime(5, 4));
      expect(p.sleepQuality!.slowOnsetNights, NightsPerWeek.oneToTwo);
      expect(HealthProfile.fromJson(p.toJson()).toJson(), p.toJson());
      expect(
        const HealthProfileInput(
          usualSleepTime: ClockTime(23, 30),
          usualWakeTime: ClockTime(7, 0),
        ).toJson(),
        {'usual_sleep_time': '23:30', 'usual_wake_time': '07:00'},
      );
    });

    test('ChronotypeAssessment', () {
      final a = ChronotypeAssessment.fromJson({
        'chronotype': 'bear',
        'spectrum': 'intermediate',
        'sleep_concern': 'none',
        'source': 'mctq',
        'mctq_result': _mctqResultJson,
        'rmeq_category': null,
        'phi_prior_hours': 18.39,
        'phi_prior_sd_hours': 1.0,
        'natural_sleep_time': '01:45',
        'natural_wake_time': '08:24',
        'sleep_shortfall_hours': 0.36,
        'typical_week': {
          'phi_hours': 18.39,
          'school_onset_shift_minutes': 0,
          'days': [
            {
              'day': 0,
              'wake_time': '06:30',
              'sleep_time': '00:30',
              'kss_08': 4.3,
              'kss_14': 4.9,
              'kss_22': 6.5,
              'worst_time': '00:25',
              'worst_kss': 7.6,
              'minutes_past_threshold': 15,
              'peak_start': '07:00',
              'peak_mean_kss': 4.2,
            },
          ],
          'points': [
            {
              'day': 0,
              'time': '09:00',
              'asleep': false,
              'alertness': 0.33,
              'kss': 4.6,
            },
          ],
        },
      });
      expect(a.naturalWakeTime, const ClockTime(8, 24));
      expect(a.typicalWeek.days.single.peakStart, const ClockTime(7, 0));
      expect(a.typicalWeek.points.single.kss, 4.6);
      expect(
        const ChronotypeAssessmentRequest(
          rmeqScore: 14,
          sleepQuality: SleepQualityAnswers(
            slowOnsetNights: NightsPerWeek.threeOrMore,
            nightWakingNights: NightsPerWeek.none,
            duration: ProblemDuration.overThreeMonths,
          ),
        ).toJson(),
        {
          'rmeq_score': 14,
          'sleep_quality': {
            'slow_onset_nights': '3+',
            'night_waking_nights': '0',
            'duration': '>3m',
          },
        },
      );
    });

    test('SleepLog, SleepDebt, Biorhythm', () {
      final log = SleepLog.fromJson({
        'id': 'x',
        'sleep_at': '2026-10-18T23:45:00+07:00',
        'wake_at': '2026-10-19T06:50:00+07:00',
        'duration_minutes': 425,
        'quality': null,
        'note': null,
        'source': 'screen_inferred',
        'confirmed': false,
        'confidence': 0.93,
        'created_at': '2026-10-19T07:10:00+07:00',
        'updated_at': '2026-10-19T07:10:00+07:00',
      });
      expect(log.wakeAt.difference(log.sleepAt).inMinutes, 425);
      expect(log.source, SleepSource.screenInferred);
      expect(log.confirmed, isFalse);

      final debt = SleepDebt.fromJson({
        'days': 7,
        'total_debt_minutes': 310,
        'average_sleep_minutes': 436,
        'social_jetlag_hours': 1.9,
        'current_process_s': 0.52,
        'daily': [
          {
            'date': '2026-10-13',
            'has_data': true,
            'slept_minutes': 400,
            'need_minutes': 480,
            'debt_minutes': 80,
            'mid_sleep': '03:10',
            'is_free_day': false,
          },
        ],
      });
      expect(debt.daily.single.date, DateTime(2026, 10, 13));
      expect(debt.daily.single.midSleep, const ClockTime(3, 10));

      final bio = Biorhythm.fromJson({
        'date': '2026-10-22',
        'days': 1,
        'interval_minutes': 15,
        'timezone': 'Asia/Ho_Chi_Minh',
        'model': _modelJson,
        'points': [
          {
            'time': '2026-10-22T19:00:00+07:00',
            'asleep': false,
            'sleep_state': 'projected',
            'process_s': 0.47,
            'process_c': 0.99,
            'upper_threshold': 0.79,
            'lower_threshold': 0.29,
            'alertness': 0.32,
            'kss_pred': 4.65,
            'kss_lo': 3.15,
            'kss_hi': 6.15,
            'alertness_score': 54,
          },
        ],
        'peak_windows': [
          {
            'start': '2026-10-22T09:30:00+07:00',
            'end': '2026-10-22T13:10:00+07:00',
            'mean_kss_pred': 3.65,
            'alertness_score': 67,
          },
        ],
        'low_windows': [],
        'projected_sleep': [
          {
            'night_of': '2026-10-22',
            'natural_sleep_at': '2026-10-23T02:07:00+07:00',
            'natural_wake_at': '2026-10-23T10:04:00+07:00',
            'required_wake_at': '2026-10-23T06:00:00+07:00',
            'recommended_sleep_at': '2026-10-22T22:00:00+07:00',
            'projected_sleep_minutes': 480,
          },
        ],
        'warnings': ['TYPICAL_WEEK'],
      });
      expect(bio.points.single.alertnessScore, 54);
      expect(bio.points.single.sleepState, SleepState.projected);
      expect(bio.model.personalizationLevel, PersonalizationLevel.personalized);
      expect(bio.peakWindows.single.meanKssPred, 3.65);
      expect(bio.projectedSleep.single.projectedSleepMinutes, 480);
      expect(bio.warnings, ['TYPICAL_WEEK']);
      expect(Biorhythm.fromJson(bio.toJson()).toJson(), bio.toJson());
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
        'created_at': '2026-10-19T08:00:00+07:00',
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
        'created_at': '2026-10-19T08:00:00+07:00',
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
        'kind': 'study',
        'source': 'scheduler',
        'subject_id': null,
        'todo_id': 't',
        'google_event_id': 'abc123',
        'sync_status': 'synced',
        'occurrence_start': null,
        'created_at': '2026-10-19T08:00:00+07:00',
        'updated_at': '2026-10-19T08:00:00+07:00',
      });
      expect(e.source, EventSource.scheduler);
      expect(e.kind, EventKind.study);
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
        'scheduled_minutes': 90,
        'completed_at': null,
        'created_at': '2026-10-19T08:00:00+07:00',
        'updated_at': '2026-10-19T08:00:00+07:00',
      });
      expect(todo.status, TodoStatus.inProgress);
      expect(todo.scheduledMinutes, 90);

      final voice = VoiceTranscription.fromJson({
        'transcript': 'Thứ sáu nộp bài tập lớn cấu trúc dữ liệu',
        'todo_draft': {
          'title': 'Nộp bài tập lớn cấu trúc dữ liệu',
          'description': null,
          'category': 'assignment',
          'priority': 'medium',
          'deadline_at': '2026-10-23T23:59:00+07:00',
          'estimated_minutes': null,
          'difficulty': null,
        },
        'parser': 'gemini',
      });
      expect(voice.todoDraft!.category, TodoCategory.assignment);
      expect(voice.todoDraft!.estimatedMinutes, isNull);
      expect(voice.parser, 'gemini');
      expect(
        VoiceTranscription.fromJson({
          'transcript': 'ừm',
          'todo_draft': null,
          'parser': 'rules',
        }).todoDraft,
        isNull,
      );
    });

    test('ScheduleSuggestion', () {
      final s = ScheduleSuggestion.fromJson({
        'suggestion_id': 's',
        'expires_at': '2026-10-22T10:00:00+07:00',
        'from': '2026-10-22',
        'to': '2026-10-25',
        'solver_status': 'OPTIMAL',
        'blocks': [
          {
            'index': 0,
            'kind': 'study',
            'todo_id': 't',
            'title': 'Bài tập lớn CTDL',
            'start_at': '2026-10-24T09:30:00+07:00',
            'end_at': '2026-10-24T11:00:00+07:00',
            'predicted_kss': 3.6,
            'alertness_score': 68,
          },
        ],
        'unscheduled': [
          {
            'todo_id': 'u',
            'reason': 'NOT_ENOUGH_TIME_BEFORE_DEADLINE',
            'missing_minutes': 60,
          },
        ],
        'stats': {
          'study_minutes': 90,
          'mean_predicted_kss': 3.6,
          'golden_hour_ratio': 1.0,
          'solve_ms': 140,
        },
        'model': _modelJson,
      });
      expect(s.blocks.single.alertnessScore, 68);
      expect(s.blocks.single.kind, EventKind.study);
      expect(s.unscheduled.single.missingMinutes, 60);
      expect(s.stats.goldenHourRatio, 1.0);
      expect(
        ScheduleRequest(
          from: DateTime(2026, 10, 22),
          to: DateTime(2026, 10, 22),
          options: const ScheduleOptions(blockMinutes: 60),
        ).toJson(),
        {
          'from': '2026-10-22',
          'to': '2026-10-22',
          'todo_ids': null,
          'options': {'block_minutes': 60},
        },
      );
    });

    test('Calendar status, reminder settings, quote', () {
      final status = CalendarStatus.fromJson({
        'connected': true,
        'google_email': 'student@gmail.com',
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
        'kss_prompt_enabled': true,
        'kss_prompts_per_day': 4,
        'kss_prompt_window': {'start': '08:00', 'end': '23:00'},
        'sleep_confirm_enabled': true,
        'motivation_enabled': true,
        'quiet_hours': {'start': '23:00', 'end': '07:00'},
      });
      expect(settings.deadlineReminderHoursBefore, [24, 2]);
      expect(settings.quietHours!.start, const ClockTime(23, 0));

      final quote = Quote.fromJson({
        'text': '...',
        'author': null,
        'source': 'fallback',
        'context': 'deadline',
      });
      expect(quote.source, QuoteSource.fallback);
      expect(quote.context, QuoteContext.deadline);
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
        const TodoCreate(title: 'x').toJson().containsKey('status'),
        isFalse,
      );
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
      expect(() => Chronotype.fromJson('evening'), throwsFormatException);
      expect(EventKind.fromJson('class'), EventKind.classSession);
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

    test('list bodies are wrapped in items', () {
      Json row(String id) => {'id': id};
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
  'onboarding_completed': true,
  'created_at': '2026-10-19T08:00:00+07:00',
  'last_login_at': '2026-10-19T08:00:00+07:00',
};

const _modelJson = {
  'phi_hours': 18.5,
  'phi_sd_hours': 0.43,
  'chi_w_hours': 18.9,
  'chi_w_sd_hours': 0.8,
  'personalization_level': 'personalized',
  'kss_days': 14,
};

const _mctqResultJson = {
  'sd_work_hours': 6.0,
  'sd_free_hours': 8.25,
  'sd_week_hours': 6.64,
  'msw': '03:30',
  'msf': '05:52',
  'msf_sc': '05:04',
  'oversleep_corrected': true,
  'social_jetlag_hours': 2.38,
  'chronotype': 'bear',
};
