/// Shared enums from `docs/openapi.yaml` (draft 2.1). Each value keeps its
/// wire string in [value]; `fromJson` throws [FormatException] on unknown
/// values.
library;

T _parse<T extends Enum>(
  List<T> values,
  String Function(T) wire,
  Object? json,
) {
  for (final v in values) {
    if (wire(v) == json) return v;
  }
  throw FormatException('Unknown ${T.toString()} value', json);
}

/// Shown as an animal (MSFsc < 04:00 / 04:00-06:00 / >= 06:00).
enum Chronotype {
  lion('lion'),
  bear('bear'),
  wolf('wolf');

  const Chronotype(this.value);
  final String value;

  static Chronotype fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// Position on the lion <-> wolf slider.
enum ChronotypeSpectrum {
  early('early'),
  slightlyEarly('slightly_early'),
  intermediate('intermediate'),
  slightlyLate('slightly_late'),
  late('late');

  const ChronotypeSpectrum(this.value);
  final String value;

  static ChronotypeSpectrum fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// Fragmented-sleep screening flag; `dolphin` is not a chronotype.
enum SleepConcern {
  none('none'),
  watch('watch'),
  dolphin('dolphin');

  const SleepConcern(this.value);
  final String value;

  static SleepConcern fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum ChronotypeSource {
  mctq('mctq'),
  rmeq('rmeq'),
  selfReport('self_report');

  const ChronotypeSource(this.value);
  final String value;

  static ChronotypeSource fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum RmeqCategory {
  definitelyMorning('definitely_morning'),
  moderatelyMorning('moderately_morning'),
  neither('neither'),
  moderatelyEvening('moderately_evening'),
  definitelyEvening('definitely_evening');

  const RmeqCategory(this.value);
  final String value;

  static RmeqCategory fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// Answer to the sleep quality questions F1 / F2.
enum NightsPerWeek {
  none('0'),
  oneToTwo('1-2'),
  threeOrMore('3+');

  const NightsPerWeek(this.value);
  final String value;

  static NightsPerWeek fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// Answer to F3.
enum ProblemDuration {
  underOneMonth('<1m'),
  oneToThreeMonths('1-3m'),
  overThreeMonths('>3m');

  const ProblemDuration(this.value);
  final String value;

  static ProblemDuration fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum SleepSource {
  manual('manual'),
  screenInferred('screen_inferred');

  const SleepSource(this.value);
  final String value;

  static SleepSource fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// Source of a biorhythm point; `typical` = questionnaire typical week.
enum SleepState {
  observed('observed'),
  projected('projected'),
  typical('typical');

  const SleepState(this.value);
  final String value;

  static SleepState fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum PersonalizationLevel {
  priorOnly('prior_only'),
  early('early'),
  developing('developing'),
  personalized('personalized');

  const PersonalizationLevel(this.value);
  final String value;

  static PersonalizationLevel fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum EventSource {
  manual('manual'),
  ocr('ocr'),
  scheduler('scheduler'),
  google('google');

  const EventSource(this.value);
  final String value;

  static EventSource fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// Calendar colour; `class` comes from the timetable.
enum EventKind {
  classSession('class'),
  study('study'),
  rest('rest'),
  bedtime('bedtime'),
  other('other');

  const EventKind(this.value);
  final String value;

  static EventKind fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum SyncStatus {
  notSynced('not_synced'),
  pending('pending'),
  synced('synced'),
  conflict('conflict'),
  error('error');

  const SyncStatus(this.value);
  final String value;

  static SyncStatus fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum TodoStatus {
  todo('todo'),
  inProgress('in_progress'),
  done('done');

  const TodoStatus(this.value);
  final String value;

  static TodoStatus fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum TodoCategory {
  study('study'),
  assignment('assignment'),
  exam('exam'),
  personal('personal'),
  other('other');

  const TodoCategory(this.value);
  final String value;

  static TodoCategory fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum Priority {
  low('low'),
  medium('medium'),
  high('high');

  const Priority(this.value);
  final String value;

  static Priority fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum JobStatus {
  queued('queued'),
  processing('processing'),
  succeeded('succeeded'),
  failed('failed');

  const JobStatus(this.value);
  final String value;

  bool get isFinished => this == succeeded || this == failed;

  static JobStatus fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum DevicePlatform {
  android('android'),
  ios('ios');

  const DevicePlatform(this.value);
  final String value;

  static DevicePlatform fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// `context` query of `GET /quotes/random`.
enum QuoteContext {
  general('general'),
  deadline('deadline'),
  sleep('sleep'),
  progress('progress');

  const QuoteContext(this.value);
  final String value;

  static QuoteContext fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

enum QuoteSource {
  gemini('gemini'),
  fallback('fallback');

  const QuoteSource(this.value);
  final String value;

  static QuoteSource fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}

/// `keep` body of `POST /calendar/conflicts/{id}/resolve`.
enum ConflictResolution {
  local('local'),
  google('google');

  const ConflictResolution(this.value);
  final String value;

  static ConflictResolution fromJson(Object? json) =>
      _parse(values, (e) => e.value, json);
  String toJson() => value;
}
