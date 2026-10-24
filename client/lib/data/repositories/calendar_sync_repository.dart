import '../api/api_client.dart';
import '../models/models.dart';

/// Google Calendar connection and sync (G1–G4, G6–G8). G5 is called by
/// Google, not the app.
abstract interface class CalendarSyncRepository {
  Future<CalendarStatus> getStatus();

  /// G6: connects (or re-grants) Calendar with a new `serverAuthCode`
  /// requested with the `calendar.events` scope.
  Future<CalendarStatus> connect(String serverAuthCode);

  /// G7: local events stay, their sync status becomes `not_synced`.
  Future<void> disconnect();

  /// G8: changes the target calendar or two-way sync.
  Future<CalendarStatus> updateSettings({String? calendarId, bool? twoWaySync});

  /// G2: pushes pending events ([eventIds] `null` → all pending) and pulls
  /// changes when two-way. Throws `ApiException` 403 `GOOGLE_SCOPE_MISSING`
  /// or 409 `CALENDAR_NOT_CONNECTED`.
  Future<SyncResult> sync({List<String>? eventIds});

  Future<List<SyncConflict>> listConflicts();

  Future<CalendarEvent> resolveConflict(String id, ConflictResolution keep);
}

class ApiCalendarSyncRepository implements CalendarSyncRepository {
  ApiCalendarSyncRepository(this._client);

  final ApiClient _client;

  @override
  Future<CalendarStatus> getStatus() async =>
      CalendarStatus.fromJson(await _client.get('calendar/status') as Json);

  @override
  Future<CalendarStatus> connect(String serverAuthCode) async =>
      CalendarStatus.fromJson(
        await _client.post(
          'calendar/connection',
          body: {'server_auth_code': serverAuthCode},
        ) as Json,
      );

  @override
  Future<void> disconnect() => _client.delete('calendar/connection');

  @override
  Future<CalendarStatus> updateSettings({
    String? calendarId,
    bool? twoWaySync,
  }) async => CalendarStatus.fromJson(
    await _client.patch(
      'calendar/settings',
      body: {'calendar_id': ?calendarId, 'two_way_sync': ?twoWaySync},
    ) as Json,
  );

  @override
  Future<SyncResult> sync({List<String>? eventIds}) async =>
      SyncResult.fromJson(
        await _client.post('calendar/sync', body: {'event_ids': eventIds})
            as Json,
      );

  @override
  Future<List<SyncConflict>> listConflicts() async => parseItems(
    await _client.get('calendar/conflicts'),
    SyncConflict.fromJson,
  );

  @override
  Future<CalendarEvent> resolveConflict(
    String id,
    ConflictResolution keep,
  ) async => CalendarEvent.fromJson(
    await _client.post(
      'calendar/conflicts/$id/resolve',
      body: {'keep': keep.toJson()},
    ) as Json,
  );
}
