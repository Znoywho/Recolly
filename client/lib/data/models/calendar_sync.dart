import 'event.dart';
import 'json_utils.dart';

/// G1 `GET /calendar/status`.
class CalendarStatus {
  const CalendarStatus({
    required this.connected,
    this.calendarId,
    required this.twoWaySync,
    this.lastSyncedAt,
    required this.pendingCount,
    required this.conflictCount,
  });

  factory CalendarStatus.fromJson(Json json) => CalendarStatus(
    connected: json['connected'] as bool,
    calendarId: json['calendar_id'] as String?,
    twoWaySync: json['two_way_sync'] as bool? ?? false,
    lastSyncedAt: parseDateTimeOrNull(json['last_synced_at']),
    pendingCount: json['pending_count'] as int? ?? 0,
    conflictCount: json['conflict_count'] as int? ?? 0,
  );

  final bool connected;
  final String? calendarId;
  final bool twoWaySync;
  final DateTime? lastSyncedAt;
  final int pendingCount;
  final int conflictCount;

  Json toJson() => {
    'connected': connected,
    'calendar_id': calendarId,
    'two_way_sync': twoWaySync,
    'last_synced_at': formatDateTimeOrNull(lastSyncedAt),
    'pending_count': pendingCount,
    'conflict_count': conflictCount,
  };
}

/// G2 `POST /calendar/sync` response.
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.failed,
    required this.conflicts,
  });

  factory SyncResult.fromJson(Json json) => SyncResult(
    pushed: json['pushed'] as int,
    failed: json['failed'] as int,
    conflicts: json['conflicts'] as int,
  );

  final int pushed;
  final int failed;
  final int conflicts;

  Json toJson() => {'pushed': pushed, 'failed': failed, 'conflicts': conflicts};
}

/// The Google side of a conflict.
class GoogleEventSnapshot {
  const GoogleEventSnapshot({
    required this.title,
    required this.startAt,
    required this.endAt,
  });

  factory GoogleEventSnapshot.fromJson(Json json) => GoogleEventSnapshot(
    title: json['title'] as String,
    startAt: parseDateTime(json['start_at']),
    endAt: parseDateTime(json['end_at']),
  );

  final String title;
  final DateTime startAt;
  final DateTime endAt;

  Json toJson() => {
    'title': title,
    'start_at': formatDateTime(startAt),
    'end_at': formatDateTime(endAt),
  };
}

/// G3 item.
class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.eventId,
    required this.local,
    required this.google,
    required this.detectedAt,
  });

  factory SyncConflict.fromJson(Json json) => SyncConflict(
    id: json['id'] as String,
    eventId: json['event_id'] as String,
    local: CalendarEvent.fromJson(json['local'] as Json),
    google: GoogleEventSnapshot.fromJson(json['google'] as Json),
    detectedAt: parseDateTime(json['detected_at']),
  );

  final String id;
  final String eventId;
  final CalendarEvent local;
  final GoogleEventSnapshot google;
  final DateTime detectedAt;

  Json toJson() => {
    'id': id,
    'event_id': eventId,
    'local': local.toJson(),
    'google': google.toJson(),
    'detected_at': formatDateTime(detectedAt),
  };
}
