import 'enums.dart';
import 'json_utils.dart';

/// Shortened MCTQ answers. "Work" = school days, "free" = days without
/// obligations; onset = falling asleep, end = waking up.
class MctqAnswers {
  const MctqAnswers({
    required this.sleepOnsetWork,
    required this.sleepEndWork,
    required this.sleepOnsetFree,
    required this.sleepEndFree,
    this.workDays,
    this.alarmOnFreeDays = false,
  });

  factory MctqAnswers.fromJson(Json json) => MctqAnswers(
    sleepOnsetWork: ClockTime.fromJson(json['sleep_onset_work']),
    sleepEndWork: ClockTime.fromJson(json['sleep_end_work']),
    sleepOnsetFree: ClockTime.fromJson(json['sleep_onset_free']),
    sleepEndFree: ClockTime.fromJson(json['sleep_end_free']),
    workDays: json['work_days'] as int?,
    alarmOnFreeDays: json['alarm_on_free_days'] as bool? ?? false,
  );

  final ClockTime sleepOnsetWork;
  final ClockTime sleepEndWork;
  final ClockTime sleepOnsetFree;
  final ClockTime sleepEndFree;

  /// School days per week (0–7). `null` → derived from the timetable.
  final int? workDays;
  final bool alarmOnFreeDays;

  Json toJson() => {
    'sleep_onset_work': sleepOnsetWork.toJson(),
    'sleep_end_work': sleepEndWork.toJson(),
    'sleep_onset_free': sleepOnsetFree.toJson(),
    'sleep_end_free': sleepEndFree.toJson(),
    'work_days': workDays,
    'alarm_on_free_days': alarmOnFreeDays,
  };
}

/// Scores computed by the server from [MctqAnswers] (read-only).
class MctqResult {
  const MctqResult({
    required this.sdWorkHours,
    required this.sdFreeHours,
    required this.sdWeekHours,
    required this.msw,
    required this.msf,
    required this.msfSc,
    required this.oversleepCorrected,
    required this.socialJetlagHours,
    required this.chronotype,
  });

  factory MctqResult.fromJson(Json json) => MctqResult(
    sdWorkHours: parseDouble(json['sd_work_hours']),
    sdFreeHours: parseDouble(json['sd_free_hours']),
    sdWeekHours: parseDouble(json['sd_week_hours']),
    msw: ClockTime.fromJson(json['msw']),
    msf: ClockTime.fromJson(json['msf']),
    msfSc: ClockTime.fromJson(json['msf_sc']),
    oversleepCorrected: json['oversleep_corrected'] as bool,
    socialJetlagHours: parseDouble(json['social_jetlag_hours']),
    chronotype: Chronotype.fromJson(json['chronotype']),
  );

  final double sdWorkHours;
  final double sdFreeHours;
  final double sdWeekHours;

  /// Mid-sleep on school days / free days.
  final ClockTime msw;
  final ClockTime msf;

  /// MSF corrected for catch-up sleep: the chronotype.
  final ClockTime msfSc;
  final bool oversleepCorrected;
  final double socialJetlagHours;
  final Chronotype chronotype;

  Json toJson() => {
    'sd_work_hours': sdWorkHours,
    'sd_free_hours': sdFreeHours,
    'sd_week_hours': sdWeekHours,
    'msw': msw.toJson(),
    'msf': msf.toJson(),
    'msf_sc': msfSc.toJson(),
    'oversleep_corrected': oversleepCorrected,
    'social_jetlag_hours': socialJetlagHours,
    'chronotype': chronotype.toJson(),
  };
}

/// Onboarding questions F1–F3 (fragmented-sleep screening).
class SleepQualityAnswers {
  const SleepQualityAnswers({
    required this.slowOnsetNights,
    required this.nightWakingNights,
    this.duration,
  });

  factory SleepQualityAnswers.fromJson(Json json) => SleepQualityAnswers(
    slowOnsetNights: NightsPerWeek.fromJson(json['slow_onset_nights']),
    nightWakingNights: NightsPerWeek.fromJson(json['night_waking_nights']),
    duration: json['duration'] == null
        ? null
        : ProblemDuration.fromJson(json['duration']),
  );

  /// F1: nights a week taking > 30 min to fall asleep.
  final NightsPerWeek slowOnsetNights;

  /// F2: nights a week waking up and unable to fall back asleep.
  final NightsPerWeek nightWakingNights;

  /// F3: only asked when F1 or F2 is `3+`.
  final ProblemDuration? duration;

  Json toJson() => {
    'slow_onset_nights': slowOnsetNights.toJson(),
    'night_waking_nights': nightWakingNights.toJson(),
    'duration': duration?.toJson(),
  };
}

/// C1 `POST /chronotype/assess` body. Needs [mctq] or [rmeqScore].
class ChronotypeAssessmentRequest {
  const ChronotypeAssessmentRequest({
    this.mctq,
    this.rmeqScore,
    this.regularSchedule,
    this.sleepQuality,
    this.schoolOnsetShiftMinutes,
  });

  final MctqAnswers? mctq;

  /// rMEQ total, 4–25.
  final int? rmeqScore;

  /// `false` (shift work, changing timetable) → rMEQ is used instead of MCTQ.
  final bool? regularSchedule;
  final SleepQualityAnswers? sleepQuality;

  /// What-if slider, −180…180; negative = fall asleep earlier on school nights.
  final int? schoolOnsetShiftMinutes;

  Json toJson() => {
    'mctq': ?mctq?.toJson(),
    'rmeq_score': ?rmeqScore,
    'regular_schedule': ?regularSchedule,
    'sleep_quality': ?sleepQuality?.toJson(),
    'school_onset_shift_minutes': ?schoolOnsetShiftMinutes,
  };
}

/// One waking period of the typical week (wake-up on [day] until the next
/// sleep onset).
class TypicalWeekDay {
  const TypicalWeekDay({
    required this.day,
    required this.wakeTime,
    required this.sleepTime,
    this.kss08,
    this.kss14,
    this.kss22,
    required this.worstTime,
    required this.worstKss,
    required this.minutesPastThreshold,
    this.peakStart,
    this.peakMeanKss,
  });

  factory TypicalWeekDay.fromJson(Json json) => TypicalWeekDay(
    day: json['day'] as int,
    wakeTime: ClockTime.fromJson(json['wake_time']),
    sleepTime: ClockTime.fromJson(json['sleep_time']),
    kss08: parseDoubleOrNull(json['kss_08']),
    kss14: parseDoubleOrNull(json['kss_14']),
    kss22: parseDoubleOrNull(json['kss_22']),
    worstTime: ClockTime.fromJson(json['worst_time']),
    worstKss: parseDouble(json['worst_kss']),
    minutesPastThreshold: json['minutes_past_threshold'] as int,
    peakStart: json['peak_start'] == null
        ? null
        : ClockTime.fromJson(json['peak_start']),
    peakMeanKss: parseDoubleOrNull(json['peak_mean_kss']),
  );

  /// 0 = Monday … 6 = Sunday.
  final int day;
  final ClockTime wakeTime;
  final ClockTime sleepTime;

  /// Predicted KSS at 08:00 / 14:00 / 22:00; `null` while asleep.
  final double? kss08;
  final double? kss14;
  final double? kss22;
  final ClockTime worstTime;
  final double worstKss;

  /// Minutes awake past the sleep threshold ("should be asleep").
  final int minutesPastThreshold;

  /// Start of the most alert 90-min block.
  final ClockTime? peakStart;
  final double? peakMeanKss;

  Json toJson() => {
    'day': day,
    'wake_time': wakeTime.toJson(),
    'sleep_time': sleepTime.toJson(),
    'kss_08': kss08,
    'kss_14': kss14,
    'kss_22': kss22,
    'worst_time': worstTime.toJson(),
    'worst_kss': worstKss,
    'minutes_past_threshold': minutesPastThreshold,
    'peak_start': peakStart?.toJson(),
    'peak_mean_kss': peakMeanKss,
  };
}

class TypicalWeekPoint {
  const TypicalWeekPoint({
    required this.day,
    required this.time,
    required this.asleep,
    required this.alertness,
    this.kss,
  });

  factory TypicalWeekPoint.fromJson(Json json) => TypicalWeekPoint(
    day: json['day'] as int,
    time: ClockTime.fromJson(json['time']),
    asleep: json['asleep'] as bool,
    alertness: parseDouble(json['alertness']),
    kss: parseDoubleOrNull(json['kss']),
  );

  final int day;
  final ClockTime time;
  final bool asleep;
  final double alertness;
  final double? kss;

  Json toJson() => {
    'day': day,
    'time': time.toJson(),
    'asleep': asleep,
    'alertness': alertness,
    'kss': kss,
  };
}

/// Two-process model run on the questionnaire sleep times.
class TypicalWeek {
  const TypicalWeek({
    required this.phiHours,
    required this.schoolOnsetShiftMinutes,
    required this.days,
    required this.points,
  });

  factory TypicalWeek.fromJson(Json json) => TypicalWeek(
    phiHours: parseDouble(json['phi_hours']),
    schoolOnsetShiftMinutes: json['school_onset_shift_minutes'] as int,
    days: parseList(json['days'], TypicalWeekDay.fromJson),
    points: parseList(json['points'], TypicalWeekPoint.fromJson),
  );

  final double phiHours;
  final int schoolOnsetShiftMinutes;

  /// 7 day summaries, Monday first.
  final List<TypicalWeekDay> days;

  /// Energy curve every 15 min for 7 days.
  final List<TypicalWeekPoint> points;

  Json toJson() => {
    'phi_hours': phiHours,
    'school_onset_shift_minutes': schoolOnsetShiftMinutes,
    'days': [for (final d in days) d.toJson()],
    'points': [for (final p in points) p.toJson()],
  };
}

/// C1 response: the onboarding result card. Not saved until H2.
class ChronotypeAssessment {
  const ChronotypeAssessment({
    required this.chronotype,
    required this.spectrum,
    required this.sleepConcern,
    required this.source,
    this.mctqResult,
    this.rmeqCategory,
    required this.phiPriorHours,
    required this.phiPriorSdHours,
    required this.naturalSleepTime,
    required this.naturalWakeTime,
    this.sleepShortfallHours,
    required this.typicalWeek,
  });

  factory ChronotypeAssessment.fromJson(Json json) => ChronotypeAssessment(
    chronotype: Chronotype.fromJson(json['chronotype']),
    spectrum: ChronotypeSpectrum.fromJson(json['spectrum']),
    sleepConcern: SleepConcern.fromJson(json['sleep_concern']),
    source: ChronotypeSource.fromJson(json['source']),
    mctqResult: json['mctq_result'] == null
        ? null
        : MctqResult.fromJson(json['mctq_result'] as Json),
    rmeqCategory: json['rmeq_category'] == null
        ? null
        : RmeqCategory.fromJson(json['rmeq_category']),
    phiPriorHours: parseDouble(json['phi_prior_hours']),
    phiPriorSdHours: parseDouble(json['phi_prior_sd_hours']),
    naturalSleepTime: ClockTime.fromJson(json['natural_sleep_time']),
    naturalWakeTime: ClockTime.fromJson(json['natural_wake_time']),
    sleepShortfallHours: parseDoubleOrNull(json['sleep_shortfall_hours']),
    typicalWeek: TypicalWeek.fromJson(json['typical_week'] as Json),
  );

  final Chronotype chronotype;
  final ChronotypeSpectrum spectrum;
  final SleepConcern sleepConcern;
  final ChronotypeSource source;
  final MctqResult? mctqResult;
  final RmeqCategory? rmeqCategory;
  final double phiPriorHours;
  final double phiPriorSdHours;

  /// When the body would sleep / wake without alarms.
  final ClockTime naturalSleepTime;
  final ClockTime naturalWakeTime;

  /// `max(0, 7 − SDweek)`; `null` when only the rMEQ is known.
  final double? sleepShortfallHours;
  final TypicalWeek typicalWeek;

  Json toJson() => {
    'chronotype': chronotype.toJson(),
    'spectrum': spectrum.toJson(),
    'sleep_concern': sleepConcern.toJson(),
    'source': source.toJson(),
    'mctq_result': mctqResult?.toJson(),
    'rmeq_category': rmeqCategory?.toJson(),
    'phi_prior_hours': phiPriorHours,
    'phi_prior_sd_hours': phiPriorSdHours,
    'natural_sleep_time': naturalSleepTime.toJson(),
    'natural_wake_time': naturalWakeTime.toJson(),
    'sleep_shortfall_hours': sleepShortfallHours,
    'typical_week': typicalWeek.toJson(),
  };
}

/// H1 / H2 sleep profile.
class HealthProfile {
  const HealthProfile({
    required this.chronotype,
    this.spectrum,
    required this.sleepConcern,
    required this.chronotypeSource,
    required this.usualSleepTime,
    required this.usualWakeTime,
    required this.sleepNeedHours,
    required this.morningPrepMinutes,
    this.mctq,
    this.mctqResult,
    this.rmeqScore,
    this.rmeqCategory,
    required this.regularSchedule,
    this.sleepQuality,
    required this.screenTrackingEnabled,
    required this.updatedAt,
  });

  factory HealthProfile.fromJson(Json json) => HealthProfile(
    chronotype: Chronotype.fromJson(json['chronotype']),
    spectrum: json['spectrum'] == null
        ? null
        : ChronotypeSpectrum.fromJson(json['spectrum']),
    sleepConcern: SleepConcern.fromJson(json['sleep_concern']),
    chronotypeSource: ChronotypeSource.fromJson(json['chronotype_source']),
    usualSleepTime: ClockTime.fromJson(json['usual_sleep_time']),
    usualWakeTime: ClockTime.fromJson(json['usual_wake_time']),
    sleepNeedHours: parseDouble(json['sleep_need_hours']),
    morningPrepMinutes: json['morning_prep_minutes'] as int,
    mctq: json['mctq'] == null
        ? null
        : MctqAnswers.fromJson(json['mctq'] as Json),
    mctqResult: json['mctq_result'] == null
        ? null
        : MctqResult.fromJson(json['mctq_result'] as Json),
    rmeqScore: json['rmeq_score'] as int?,
    rmeqCategory: json['rmeq_category'] == null
        ? null
        : RmeqCategory.fromJson(json['rmeq_category']),
    regularSchedule: json['regular_schedule'] as bool,
    sleepQuality: json['sleep_quality'] == null
        ? null
        : SleepQualityAnswers.fromJson(json['sleep_quality'] as Json),
    screenTrackingEnabled: json['screen_tracking_enabled'] as bool,
    updatedAt: parseDateTime(json['updated_at']),
  );

  final Chronotype chronotype;

  /// `null` for a self-reported chronotype.
  final ChronotypeSpectrum? spectrum;
  final SleepConcern sleepConcern;
  final ChronotypeSource chronotypeSource;
  final ClockTime usualSleepTime;
  final ClockTime usualWakeTime;
  final double sleepNeedHours;

  /// Minutes between waking and the first class (sets the projected alarm).
  final int morningPrepMinutes;
  final MctqAnswers? mctq;
  final MctqResult? mctqResult;
  final int? rmeqScore;
  final RmeqCategory? rmeqCategory;
  final bool regularSchedule;
  final SleepQualityAnswers? sleepQuality;
  final bool screenTrackingEnabled;
  final DateTime updatedAt;

  Json toJson() => {
    'chronotype': chronotype.toJson(),
    'spectrum': spectrum?.toJson(),
    'sleep_concern': sleepConcern.toJson(),
    'chronotype_source': chronotypeSource.toJson(),
    'usual_sleep_time': usualSleepTime.toJson(),
    'usual_wake_time': usualWakeTime.toJson(),
    'sleep_need_hours': sleepNeedHours,
    'morning_prep_minutes': morningPrepMinutes,
    'mctq': mctq?.toJson(),
    'mctq_result': mctqResult?.toJson(),
    'rmeq_score': rmeqScore,
    'rmeq_category': rmeqCategory?.toJson(),
    'regular_schedule': regularSchedule,
    'sleep_quality': sleepQuality?.toJson(),
    'screen_tracking_enabled': screenTrackingEnabled,
    'updated_at': formatDateTime(updatedAt),
  };
}

/// H2 `PUT /health-profile` body. When [mctq] or [rmeqScore] is given the
/// server computes the chronotype and ignores [chronotype].
class HealthProfileInput {
  const HealthProfileInput({
    this.chronotype,
    required this.usualSleepTime,
    required this.usualWakeTime,
    this.sleepNeedHours,
    this.morningPrepMinutes,
    this.mctq,
    this.rmeqScore,
    this.regularSchedule,
    this.sleepQuality,
    this.screenTrackingEnabled,
  });

  final Chronotype? chronotype;
  final ClockTime usualSleepTime;
  final ClockTime usualWakeTime;

  /// 4–12, default 8.
  final double? sleepNeedHours;

  /// 0–180, default 60.
  final int? morningPrepMinutes;
  final MctqAnswers? mctq;
  final int? rmeqScore;
  final bool? regularSchedule;
  final SleepQualityAnswers? sleepQuality;
  final bool? screenTrackingEnabled;

  Json toJson() => {
    'chronotype': ?chronotype?.toJson(),
    'usual_sleep_time': usualSleepTime.toJson(),
    'usual_wake_time': usualWakeTime.toJson(),
    'sleep_need_hours': ?sleepNeedHours,
    'morning_prep_minutes': ?morningPrepMinutes,
    'mctq': ?mctq?.toJson(),
    'rmeq_score': ?rmeqScore,
    'regular_schedule': ?regularSchedule,
    'sleep_quality': ?sleepQuality?.toJson(),
    'screen_tracking_enabled': ?screenTrackingEnabled,
  };
}
