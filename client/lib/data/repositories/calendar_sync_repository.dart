import '../api/api_client.dart';
import '../models/models.dart';

/// Google Calendar sync (G1–G4). G5 is called by Google, not the app.
abstract interface class CalendarSyncRepository {
  Future<CalendarStatus> getStatus();

  /// G2: pushes pending events. Throws `ApiException` 403
  /// `GOOGLE_SCOPE_MISSING` if the Calendar scope was not granted.
  Future<SyncResult> sync();

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
  Future<SyncResult> sync() async =>
      SyncResult.fromJson(await _client.post('calendar/sync') as Json);

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
