import 'enums.dart';
import 'json_utils.dart';

/// Event object (E1–E5). Named `CalendarEvent` to avoid clashing with other
/// `Event` types in Flutter code.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startAt,
    required this.endAt,
    this.allDay = false,
    this.rrule,
    this.kind = EventKind.other,
    required this.source,
    this.subjectId,
    this.todoId,
    this.googleEventId,
    this.syncStatus = SyncStatus.notSynced,
    this.occurrenceStart,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CalendarEvent.fromJson(Json json) => CalendarEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    location: json['location'] as String?,
    startAt: parseDateTime(json['start_at']),
    endAt: parseDateTime(json['end_at']),
    allDay: json['all_day'] as bool,
    rrule: json['rrule'] as String?,
    kind: EventKind.fromJson(json['kind']),
    source: EventSource.fromJson(json['source']),
    subjectId: json['subject_id'] as String?,
    todoId: json['todo_id'] as String?,
    googleEventId: json['google_event_id'] as String?,
    syncStatus: SyncStatus.fromJson(json['sync_status']),
    occurrenceStart: parseDateTimeOrNull(json['occurrence_start']),
    createdAt: parseDateTime(json['created_at']),
    updatedAt: parseDateTime(json['updated_at']),
  );

  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;

  /// RFC 5545 RRULE, e.g. `FREQ=WEEKLY;BYDAY=MO`.
  final String? rrule;
  final EventKind kind;
  final EventSource source;
  final String? subjectId;
  final String? todoId;
  final String? googleEventId;
  final SyncStatus syncStatus;

  /// Set on instances of a recurring event expanded by E1. Edits and
  /// deletes through [id] act on the whole series.
  final DateTime? occurrenceStart;
  final DateTime createdAt;
  final DateTime updatedAt;

  Json toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'location': location,
    'start_at': formatDateTime(startAt),
    'end_at': formatDateTime(endAt),
    'all_day': allDay,
    'rrule': rrule,
    'kind': kind.toJson(),
    'source': source.toJson(),
    'subject_id': subjectId,
    'todo_id': todoId,
    'google_event_id': googleEventId,
    'sync_status': syncStatus.toJson(),
    'occurrence_start': formatDateTimeOrNull(occurrenceStart),
    'created_at': formatDateTime(createdAt),
    'updated_at': formatDateTime(updatedAt),
  };
}

/// E2 `POST /events` body.
class EventCreate {
  const EventCreate({
    required this.title,
    this.description,
    this.location,
    required this.startAt,
    required this.endAt,
    this.allDay = false,
    this.rrule,
    this.kind = EventKind.other,
    this.todoId,
  });

  final String title;
  final String? description;
  final String? location;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final String? rrule;

  /// `class` is reserved for timetable events.
  final EventKind kind;
  final String? todoId;

  Json toJson() => {
    'title': title,
    'description': description,
    'location': location,
    'start_at': formatDateTime(startAt),
    'end_at': formatDateTime(endAt),
    'all_day': allDay,
    'rrule': rrule,
    'kind': kind.toJson(),
    'todo_id': todoId,
  };
}

/// E4 `PATCH /events/{id}` body. A synced event goes back to `pending`.
class EventUpdate {
  const EventUpdate({
    this.title,
    this.description,
    this.location,
    this.startAt,
    this.endAt,
    this.allDay,
    this.rrule,
    this.kind,
    this.todoId,
  });

  final String? title;
  final Nullable<String>? description;
  final Nullable<String>? location;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool? allDay;
  final Nullable<String>? rrule;
  final EventKind? kind;
  final Nullable<String>? todoId;

  Json toJson() {
    final json = <String, Object?>{
      'title': ?title,
      'start_at': ?formatDateTimeOrNull(startAt),
      'end_at': ?formatDateTimeOrNull(endAt),
      'all_day': ?allDay,
      'kind': ?kind?.toJson(),
    };
    putNullable(json, 'description', description);
    putNullable(json, 'location', location);
    putNullable(json, 'rrule', rrule);
    putNullable(json, 'todo_id', todoId);
    return json;
  }
}
