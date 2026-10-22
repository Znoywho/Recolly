import 'enums.dart';
import 'json_utils.dart';

/// H1 / H2 sleep profile.
class HealthProfile {
  const HealthProfile({
    required this.chronotype,
    required this.usualSleepTime,
    required this.usualWakeTime,
    required this.sleepNeedHours,
  });

  factory HealthProfile.fromJson(Json json) => HealthProfile(
    chronotype: Chronotype.fromJson(json['chronotype']),
    usualSleepTime: ClockTime.fromJson(json['usual_sleep_time']),
    usualWakeTime: ClockTime.fromJson(json['usual_wake_time']),
    sleepNeedHours: parseDouble(json['sleep_need_hours']),
  );

  final Chronotype chronotype;
  final ClockTime usualSleepTime;
  final ClockTime usualWakeTime;
  final double sleepNeedHours;

  Json toJson() => {
    'chronotype': chronotype.toJson(),
    'usual_sleep_time': usualSleepTime.toJson(),
    'usual_wake_time': usualWakeTime.toJson(),
    'sleep_need_hours': sleepNeedHours,
  };
}

class SleepLog {
  const SleepLog({
    required this.id,
    required this.sleepAt,
    required this.wakeAt,
    required this.durationMinutes,
    this.quality,
    this.note,
  });

  factory SleepLog.fromJson(Json json) => SleepLog(
    id: json['id'] as String,
    sleepAt: parseDateTime(json['sleep_at']),
    wakeAt: parseDateTime(json['wake_at']),
    durationMinutes: json['duration_minutes'] as int,
    quality: json['quality'] as int?,
    note: json['note'] as String?,
  );

  final String id;
  final DateTime sleepAt;
  final DateTime wakeAt;

  /// Computed by the server (read-only).
  final int durationMinutes;

  /// 1–5.
  final int? quality;
  final String? note;

  Json toJson() => {
    'id': id,
    'sleep_at': formatDateTime(sleepAt),
    'wake_at': formatDateTime(wakeAt),
    'duration_minutes': durationMinutes,
    'quality': quality,
    'note': note,
  };
}

/// H4 `POST /sleep-logs` body.
class SleepLogCreate {
  const SleepLogCreate({
    required this.sleepAt,
    required this.wakeAt,
    this.quality,
    this.note,
  });

  final DateTime sleepAt;
  final DateTime wakeAt;
  final int? quality;
  final String? note;

  Json toJson() => {
    'sleep_at': formatDateTime(sleepAt),
    'wake_at': formatDateTime(wakeAt),
    'quality': quality,
    'note': note,
  };
}

/// H5 `PATCH /sleep-logs/{id}` body.
class SleepLogUpdate {
  const SleepLogUpdate({this.sleepAt, this.wakeAt, this.quality, this.note});

  final DateTime? sleepAt;
  final DateTime? wakeAt;
  final Nullable<int>? quality;
  final Nullable<String>? note;

  Json toJson() {
    final json = <String, Object?>{
      'sleep_at': ?formatDateTimeOrNull(sleepAt),
      'wake_at': ?formatDateTimeOrNull(wakeAt),
    };
    putNullable(json, 'quality', quality);
    putNullable(json, 'note', note);
    return json;
  }
}

/// H7 `GET /sleep-debt`.
class SleepDebt {
  const SleepDebt({
    required this.days,
    required this.totalDebtMinutes,
    required this.daily,
  });

  factory SleepDebt.fromJson(Json json) => SleepDebt(
    days: json['days'] as int,
    totalDebtMinutes: json['total_debt_minutes'] as int,
    daily: parseList(json['daily'], SleepDebtDay.fromJson),
  );

  final int days;
  final int totalDebtMinutes;
  final List<SleepDebtDay> daily;

  Json toJson() => {
    'days': days,
    'total_debt_minutes': totalDebtMinutes,
    'daily': [for (final d in daily) d.toJson()],
  };
}

class SleepDebtDay {
  const SleepDebtDay({
    required this.date,
    required this.sleptMinutes,
    required this.needMinutes,
    required this.debtMinutes,
  });

  factory SleepDebtDay.fromJson(Json json) => SleepDebtDay(
    date: parseDate(json['date']),
    sleptMinutes: json['slept_minutes'] as int,
    needMinutes: json['need_minutes'] as int,
    debtMinutes: json['debt_minutes'] as int,
  );

  final DateTime date;
  final int sleptMinutes;
  final int needMinutes;
  final int debtMinutes;

  Json toJson() => {
    'date': formatDate(date),
    'slept_minutes': sleptMinutes,
    'need_minutes': needMinutes,
    'debt_minutes': debtMinutes,
  };
}

/// H8 `GET /biorhythm` — Process S/C alertness curve for one day.
class Biorhythm {
  const Biorhythm({
    required this.date,
    required this.intervalMinutes,
    required this.points,
    required this.peakWindows,
    required this.lowWindows,
  });

  factory Biorhythm.fromJson(Json json) => Biorhythm(
    date: parseDate(json['date']),
    intervalMinutes: json['interval_minutes'] as int,
    points: parseList(json['points'], BiorhythmPoint.fromJson),
    peakWindows: parseList(json['peak_windows'], TimeWindow.fromJson),
    lowWindows: parseList(json['low_windows'], TimeWindow.fromJson),
  );

  final DateTime date;
  final int intervalMinutes;
  final List<BiorhythmPoint> points;
  final List<TimeWindow> peakWindows;
  final List<TimeWindow> lowWindows;

  Json toJson() => {
    'date': formatDate(date),
    'interval_minutes': intervalMinutes,
    'points': [for (final p in points) p.toJson()],
    'peak_windows': [for (final w in peakWindows) w.toJson()],
    'low_windows': [for (final w in lowWindows) w.toJson()],
  };
}

/// One sample of the curve; values are normalized to 0–1.
class BiorhythmPoint {
  const BiorhythmPoint({
    required this.time,
    required this.processS,
    required this.processC,
    required this.alertness,
  });

  factory BiorhythmPoint.fromJson(Json json) => BiorhythmPoint(
    time: parseDateTime(json['time']),
    processS: parseDouble(json['process_s']),
    processC: parseDouble(json['process_c']),
    alertness: parseDouble(json['alertness']),
  );

  final DateTime time;
  final double processS;
  final double processC;
  final double alertness;

  Json toJson() => {
    'time': formatDateTime(time),
    'process_s': processS,
    'process_c': processC,
    'alertness': alertness,
  };
}

class TimeWindow {
  const TimeWindow({required this.start, required this.end});

  factory TimeWindow.fromJson(Json json) => TimeWindow(
    start: parseDateTime(json['start']),
    end: parseDateTime(json['end']),
  );

  final DateTime start;
  final DateTime end;

  Json toJson() => {'start': formatDateTime(start), 'end': formatDateTime(end)};
}
