import 'event.dart';
import 'json_utils.dart';
import 'sleep.dart';
import 'todo.dart';

/// Model state right now (Home screen gauge).
class NowState {
  const NowState({
    required this.time,
    required this.asleep,
    required this.processS,
    required this.processC,
    this.kssPred,
    this.kssLo,
    this.kssHi,
    this.alertnessScore,
  });

  factory NowState.fromJson(Json json) => NowState(
    time: parseDateTime(json['time']),
    asleep: json['asleep'] as bool,
    processS: parseDouble(json['process_s']),
    processC: parseDouble(json['process_c']),
    kssPred: parseDoubleOrNull(json['kss_pred']),
    kssLo: parseDoubleOrNull(json['kss_lo']),
    kssHi: parseDoubleOrNull(json['kss_hi']),
    alertnessScore: json['alertness_score'] as int?,
  );

  final DateTime time;

  /// True if the model expects the user to be asleep now.
  final bool asleep;
  final double processS;
  final double processC;
  final double? kssPred;
  final double? kssLo;
  final double? kssHi;
  final int? alertnessScore;

  Json toJson() => {
    'time': formatDateTime(time),
    'asleep': asleep,
    'process_s': processS,
    'process_c': processC,
    'kss_pred': kssPred,
    'kss_lo': kssLo,
    'kss_hi': kssHi,
    'alertness_score': alertnessScore,
  };
}

/// O1 `GET /home`: everything the Home screen needs in one call.
class HomeOverview {
  const HomeOverview({
    required this.date,
    required this.now,
    this.nextPeakWindow,
    this.tonight,
    required this.todayEvents,
    required this.upcomingTodos,
    required this.sleepDebt7dMinutes,
    this.lastNight,
    required this.needsSleepConfirmation,
    required this.kssCheckinDue,
    required this.model,
  });

  factory HomeOverview.fromJson(Json json) => HomeOverview(
    date: parseDate(json['date']),
    now: NowState.fromJson(json['now'] as Json),
    nextPeakWindow: json['next_peak_window'] == null
        ? null
        : BiorhythmWindow.fromJson(json['next_peak_window'] as Json),
    tonight: json['tonight'] == null
        ? null
        : ProjectedSleep.fromJson(json['tonight'] as Json),
    todayEvents: parseList(json['today_events'], CalendarEvent.fromJson),
    upcomingTodos: parseList(json['upcoming_todos'], Todo.fromJson),
    sleepDebt7dMinutes: json['sleep_debt_7d_minutes'] as int,
    lastNight: json['last_night'] == null
        ? null
        : SleepLog.fromJson(json['last_night'] as Json),
    needsSleepConfirmation: json['needs_sleep_confirmation'] as bool,
    kssCheckinDue: json['kss_checkin_due'] as bool,
    model: ModelSummary.fromJson(json['model'] as Json),
  );

  final DateTime date;
  final NowState now;
  final BiorhythmWindow? nextPeakWindow;
  final ProjectedSleep? tonight;

  /// At most 10.
  final List<CalendarEvent> todayEvents;

  /// At most 3, not done, nearest deadline first.
  final List<Todo> upcomingTodos;
  final int sleepDebt7dMinutes;
  final SleepLog? lastNight;

  /// [lastNight] is inferred and unconfirmed → show the 1-tap confirm card.
  final bool needsSleepConfirmation;
  final bool kssCheckinDue;
  final ModelSummary model;

  Json toJson() => {
    'date': formatDate(date),
    'now': now.toJson(),
    'next_peak_window': nextPeakWindow?.toJson(),
    'tonight': tonight?.toJson(),
    'today_events': [for (final e in todayEvents) e.toJson()],
    'upcoming_todos': [for (final t in upcomingTodos) t.toJson()],
    'sleep_debt_7d_minutes': sleepDebt7dMinutes,
    'last_night': lastNight?.toJson(),
    'needs_sleep_confirmation': needsSleepConfirmation,
    'kss_checkin_due': kssCheckinDue,
    'model': model.toJson(),
  };
}
