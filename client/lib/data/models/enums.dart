/// Shared enums from `docs/api-v1.md` section 2. Each value keeps its wire
/// string in [value]; `fromJson` throws [FormatException] on unknown values.
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

enum Chronotype {
  morning('morning'),
  intermediate('intermediate'),
  evening('evening');

  const Chronotype(this.value);
  final String value;

  static Chronotype fromJson(Object? json) =>
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
