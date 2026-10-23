/// Shared JSON helpers for DTOs. Formats follow `docs/openapi.yaml`
/// (draft 2.1) conventions.
library;

typedef Json = Map<String, Object?>;

/// Parses an ISO 8601 datetime with offset and converts it to device-local
/// time, which is what screens display.
DateTime parseDateTime(Object? value) =>
    DateTime.parse(value as String).toLocal();

DateTime? parseDateTimeOrNull(Object? value) =>
    value == null ? null : parseDateTime(value);

/// Encodes as UTC ISO 8601 (`...Z`), an unambiguous offset for the server.
String formatDateTime(DateTime value) => value.toUtc().toIso8601String();

String? formatDateTimeOrNull(DateTime? value) =>
    value == null ? null : formatDateTime(value);

/// Parses `YYYY-MM-DD` as a local date at midnight.
DateTime parseDate(Object? value) {
  final d = DateTime.parse(value as String);
  return DateTime(d.year, d.month, d.day);
}

DateTime? parseDateOrNull(Object? value) =>
    value == null ? null : parseDate(value);

String formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String? formatDateOrNull(DateTime? value) =>
    value == null ? null : formatDate(value);

double parseDouble(Object? value) => (value as num).toDouble();

double? parseDoubleOrNull(Object? value) => (value as num?)?.toDouble();

List<T> parseList<T>(Object? value, T Function(Json json) fromJson) =>
    (value as List).cast<Json>().map(fromJson).toList();

/// List endpoints answer `{ "items": [...] }` (only D1 adds `next_cursor`).
List<T> parseItems<T>(Object? body, T Function(Json json) fromJson) =>
    parseList((body as Json)['items'], fromJson);

/// Wall-clock time `HH:MM` without a date (usual sleep time, class start).
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  factory ClockTime.parse(String value) {
    final parts = value.split(':');
    if (parts.length < 2) throw FormatException('Invalid time', value);
    return ClockTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  factory ClockTime.fromJson(Object? value) => ClockTime.parse(value as String);

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  /// This time on the given date, in local time.
  DateTime on(DateTime date) =>
      DateTime(date.year, date.month, date.day, hour, minute);

  String toJson() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ClockTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => toJson();
}

/// Daily window such as quiet hours or a meal break. `end < start` means it
/// crosses midnight.
class ClockWindow {
  const ClockWindow({required this.start, required this.end});

  factory ClockWindow.fromJson(Json json) => ClockWindow(
    start: ClockTime.fromJson(json['start']),
    end: ClockTime.fromJson(json['end']),
  );

  final ClockTime start;
  final ClockTime end;

  Json toJson() => {'start': start.toJson(), 'end': end.toJson()};
}

/// Wraps a new value for a nullable field in a PATCH body, so "set to null"
/// can be told apart from "leave unchanged" (field omitted).
///
/// ```dart
/// TodoUpdate(description: const Nullable(null)) // clears description
/// TodoUpdate(title: 'New')                      // description untouched
/// ```
class Nullable<T> {
  const Nullable(this.value);

  final T? value;
}

/// Adds `key: encode(value)` to a PATCH body when [field] was provided.
void putNullable<T>(
  Json json,
  String key,
  Nullable<T>? field, [
  Object? Function(T value)? encode,
]) {
  if (field == null) return;
  final value = field.value;
  json[key] = value == null ? null : (encode == null ? value : encode(value));
}
