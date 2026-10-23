import 'enums.dart';
import 'json_utils.dart';

class SleepLog {
  const SleepLog({
    required this.id,
    required this.sleepAt,
    required this.wakeAt,
    required this.durationMinutes,
    this.quality,
    this.note,
    this.source = SleepSource.manual,
    this.confirmed = true,
    this.confidence,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SleepLog.fromJson(Json json) => SleepLog(
    id: json['id'] as String,
    sleepAt: parseDateTime(json['sleep_at']),
    wakeAt: parseDateTime(json['wake_at']),
    durationMinutes: json['duration_minutes'] as int,
    quality: json['quality'] as int?,
    note: json['note'] as String?,
    source: SleepSource.fromJson(json['source']),
    confirmed: json['confirmed'] as bool,
    confidence: parseDoubleOrNull(json['confidence']),
    createdAt: parseDateTime(json['created_at']),
    updatedAt: parseDateTime(json['updated_at']),
  );

  final String id;
  final DateTime sleepAt;
  final DateTime wakeAt;

  /// Computed by the server (read-only).
  final int durationMinutes;

  /// 1–5.
  final int? quality;
  final String? note;
  final SleepSource source;

  /// Always true for manual logs.
  final bool confirmed;

  /// Inference confidence 0–1; `null` for manual logs.
  final double? confidence;
  final DateTime createdAt;
  final DateTime updatedAt;

  Json toJson() => {
    'id': id,
    'sleep_at': formatDateTime(sleepAt),
    'wake_at': formatDateTime(wakeAt),
    'duration_minutes': durationMinutes,
    'quality': quality,
    'note': note,
    'source': source.toJson(),
    'confirmed': confirmed,
    'confidence': confidence,
    'created_at': formatDateTime(createdAt),
    'updated_at': formatDateTime(updatedAt),
  };
}

/// H4 `POST /sleep-logs` body. `wake_at` after `sleep_at`, at most 16 h.
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
    this.averageSleepMinutes,
    this.socialJetlagHours,
    required this.currentProcessS,
    required this.daily,
  });

  factory SleepDebt.fromJson(Json json) => SleepDebt(
    days: json['days'] as int,
    totalDebtMinutes: json['total_debt_minutes'] as int,
    averageSleepMinutes: json['average_sleep_minutes'] as int?,
    socialJetlagHours: parseDoubleOrNull(json['social_jetlag_hours']),
    currentProcessS: parseDouble(json['current_process_s']),
    daily: parseList(json['daily'], SleepDebtDay.fromJson),
  );

  final int days;

  /// `max(0, Σ debt_minutes)` over days with data.
  final int totalDebtMinutes;
  final int? averageSleepMinutes;

  /// `null` without both school and free days.
  final double? socialJetlagHours;

  /// Sleep pressure right now, 0–1.
  final double currentProcessS;
  final List<SleepDebtDay> daily;

  Json toJson() => {
    'days': days,
    'total_debt_minutes': totalDebtMinutes,
    'average_sleep_minutes': averageSleepMinutes,
    'social_jetlag_hours': socialJetlagHours,
    'current_process_s': currentProcessS,
    'daily': [for (final d in daily) d.toJson()],
  };
}

class SleepDebtDay {
  const SleepDebtDay({
    required this.date,
    required this.hasData,
    required this.sleptMinutes,
    required this.needMinutes,
    required this.debtMinutes,
    this.midSleep,
    required this.isFreeDay,
  });

  factory SleepDebtDay.fromJson(Json json) => SleepDebtDay(
    date: parseDate(json['date']),
    hasData: json['has_data'] as bool,
    sleptMinutes: json['slept_minutes'] as int,
    needMinutes: json['need_minutes'] as int,
    debtMinutes: json['debt_minutes'] as int,
    midSleep: json['mid_sleep'] == null
        ? null
        : ClockTime.fromJson(json['mid_sleep']),
    isFreeDay: json['is_free_day'] as bool,
  );

  /// Date of waking up.
  final DateTime date;

  /// `false` → no log ends on this date; [sleptMinutes] is unknown, not 0.
  final bool hasData;
  final int sleptMinutes;
  final int needMinutes;

  /// `need − slept`; negative = extra sleep that pays back debt.
  final int debtMinutes;
  final ClockTime? midSleep;

  /// No class on this date.
  final bool isFreeDay;

  Json toJson() => {
    'date': formatDate(date),
    'has_data': hasData,
    'slept_minutes': sleptMinutes,
    'need_minutes': needMinutes,
    'debt_minutes': debtMinutes,
    'mid_sleep': midSleep?.toJson(),
    'is_free_day': isFreeDay,
  };
}

/// Personal model parameters (φ, χw) and how far they are personalised.
class ModelSummary {
  const ModelSummary({
    required this.phiHours,
    required this.phiSdHours,
    required this.chiWHours,
    required this.chiWSdHours,
    required this.personalizationLevel,
    required this.kssDays,
  });

  factory ModelSummary.fromJson(Json json) => ModelSummary(
    phiHours: parseDouble(json['phi_hours']),
    phiSdHours: parseDouble(json['phi_sd_hours']),
    chiWHours: parseDouble(json['chi_w_hours']),
    chiWSdHours: parseDouble(json['chi_w_sd_hours']),
    personalizationLevel: PersonalizationLevel.fromJson(
      json['personalization_level'],
    ),
    kssDays: json['kss_days'] as int,
  );

  /// Hour of the circadian peak (the chronotype).
  final double phiHours;
  final double phiSdHours;
  final double chiWHours;
  final double chiWSdHours;
  final PersonalizationLevel personalizationLevel;
  final int kssDays;

  Json toJson() => {
    'phi_hours': phiHours,
    'phi_sd_hours': phiSdHours,
    'chi_w_hours': chiWHours,
    'chi_w_sd_hours': chiWSdHours,
    'personalization_level': personalizationLevel.toJson(),
    'kss_days': kssDays,
  };
}

/// H8 `GET /biorhythm`: Process S/C curves, predicted KSS and golden hours.
class Biorhythm {
  const Biorhythm({
    required this.date,
    required this.days,
    required this.intervalMinutes,
    required this.timezone,
    required this.model,
    required this.points,
    required this.peakWindows,
    required this.lowWindows,
    required this.projectedSleep,
    this.warnings = const [],
  });

  factory Biorhythm.fromJson(Json json) => Biorhythm(
    date: parseDate(json['date']),
    days: json['days'] as int,
    intervalMinutes: json['interval_minutes'] as int,
    timezone: json['timezone'] as String,
    model: ModelSummary.fromJson(json['model'] as Json),
    points: parseList(json['points'], BiorhythmPoint.fromJson),
    peakWindows: parseList(json['peak_windows'], BiorhythmWindow.fromJson),
    lowWindows: parseList(json['low_windows'], BiorhythmWindow.fromJson),
    projectedSleep: parseList(json['projected_sleep'], ProjectedSleep.fromJson),
    warnings: (json['warnings'] as List).cast<String>(),
  );

  final DateTime date;
  final int days;
  final int intervalMinutes;
  final String timezone;
  final ModelSummary model;
  final List<BiorhythmPoint> points;

  /// Golden hours.
  final List<BiorhythmWindow> peakWindows;
  final List<BiorhythmWindow> lowWindows;
  final List<ProjectedSleep> projectedSleep;

  /// `TYPICAL_WEEK`, `NO_RECENT_SLEEP_DATA`, `UNCONFIRMED_SLEEP_DATA`,
  /// `PRIOR_ONLY`: show a hint, still render the chart.
  final List<String> warnings;

  Json toJson() => {
    'date': formatDate(date),
    'days': days,
    'interval_minutes': intervalMinutes,
    'timezone': timezone,
    'model': model.toJson(),
    'points': [for (final p in points) p.toJson()],
    'peak_windows': [for (final w in peakWindows) w.toJson()],
    'low_windows': [for (final w in lowWindows) w.toJson()],
    'projected_sleep': [for (final s in projectedSleep) s.toJson()],
    'warnings': warnings,
  };
}

/// One sample of the curve. Raw model values: `processC` is −1…1 and
/// `alertness` may be negative; use [alertnessScore] (0–100) in the UI.
/// KSS fields and [alertnessScore] are `null` while asleep.
class BiorhythmPoint {
  const BiorhythmPoint({
    required this.time,
    required this.asleep,
    required this.sleepState,
    required this.processS,
    required this.processC,
    required this.upperThreshold,
    required this.lowerThreshold,
    required this.alertness,
    this.kssPred,
    this.kssLo,
    this.kssHi,
    this.alertnessScore,
  });

  factory BiorhythmPoint.fromJson(Json json) => BiorhythmPoint(
    time: parseDateTime(json['time']),
    asleep: json['asleep'] as bool,
    sleepState: SleepState.fromJson(json['sleep_state']),
    processS: parseDouble(json['process_s']),
    processC: parseDouble(json['process_c']),
    upperThreshold: parseDouble(json['upper_threshold']),
    lowerThreshold: parseDouble(json['lower_threshold']),
    alertness: parseDouble(json['alertness']),
    kssPred: parseDoubleOrNull(json['kss_pred']),
    kssLo: parseDoubleOrNull(json['kss_lo']),
    kssHi: parseDoubleOrNull(json['kss_hi']),
    alertnessScore: json['alertness_score'] as int?,
  );

  final DateTime time;
  final bool asleep;
  final SleepState sleepState;
  final double processS;
  final double processC;
  final double upperThreshold;
  final double lowerThreshold;
  final double alertness;

  /// Predicted KSS (1 very alert … 9 fighting sleep) and its 95 % interval.
  final double? kssPred;
  final double? kssLo;
  final double? kssHi;
  final int? alertnessScore;

  Json toJson() => {
    'time': formatDateTime(time),
    'asleep': asleep,
    'sleep_state': sleepState.toJson(),
    'process_s': processS,
    'process_c': processC,
    'upper_threshold': upperThreshold,
    'lower_threshold': lowerThreshold,
    'alertness': alertness,
    'kss_pred': kssPred,
    'kss_lo': kssLo,
    'kss_hi': kssHi,
    'alertness_score': alertnessScore,
  };
}

/// A golden-hour (peak) or low window.
class BiorhythmWindow {
  const BiorhythmWindow({
    required this.start,
    required this.end,
    required this.meanKssPred,
    required this.alertnessScore,
  });

  factory BiorhythmWindow.fromJson(Json json) => BiorhythmWindow(
    start: parseDateTime(json['start']),
    end: parseDateTime(json['end']),
    meanKssPred: parseDouble(json['mean_kss_pred']),
    alertnessScore: json['alertness_score'] as int,
  );

  final DateTime start;
  final DateTime end;
  final double meanKssPred;
  final int alertnessScore;

  Json toJson() => {
    'start': formatDateTime(start),
    'end': formatDateTime(end),
    'mean_kss_pred': meanKssPred,
    'alertness_score': alertnessScore,
  };
}

/// Sleep plan for one night.
class ProjectedSleep {
  const ProjectedSleep({
    required this.nightOf,
    required this.naturalSleepAt,
    required this.naturalWakeAt,
    this.requiredWakeAt,
    required this.recommendedSleepAt,
    required this.projectedSleepMinutes,
  });

  factory ProjectedSleep.fromJson(Json json) => ProjectedSleep(
    nightOf: parseDate(json['night_of']),
    naturalSleepAt: parseDateTime(json['natural_sleep_at']),
    naturalWakeAt: parseDateTime(json['natural_wake_at']),
    requiredWakeAt: parseDateTimeOrNull(json['required_wake_at']),
    recommendedSleepAt: parseDateTime(json['recommended_sleep_at']),
    projectedSleepMinutes: json['projected_sleep_minutes'] as int,
  );

  final DateTime nightOf;
  final DateTime naturalSleepAt;
  final DateTime naturalWakeAt;

  /// First class tomorrow − morning prep; `null` if no class.
  final DateTime? requiredWakeAt;

  /// Drives the bedtime reminder.
  final DateTime recommendedSleepAt;
  final int projectedSleepMinutes;

  Json toJson() => {
    'night_of': formatDate(nightOf),
    'natural_sleep_at': formatDateTime(naturalSleepAt),
    'natural_wake_at': formatDateTime(naturalWakeAt),
    'required_wake_at': formatDateTimeOrNull(requiredWakeAt),
    'recommended_sleep_at': formatDateTime(recommendedSleepAt),
    'projected_sleep_minutes': projectedSleepMinutes,
  };
}
