import '../api/api_client.dart';
import '../models/models.dart';

/// CP-SAT study schedule (S1, S2).
abstract interface class ScheduleRepository {
  /// S1: suggested study blocks (not saved, expire after 1 hour).
  Future<ScheduleSuggestion> generate(ScheduleRequest request);

  /// S2: saves the chosen blocks as events. [blockIndexes] `null` → all.
  Future<List<CalendarEvent>> apply(
    String suggestionId, {
    List<int>? blockIndexes,
    bool syncToGoogle = false,
  });
}

class ApiScheduleRepository implements ScheduleRepository {
  ApiScheduleRepository(this._client);

  final ApiClient _client;

  @override
  Future<ScheduleSuggestion> generate(ScheduleRequest request) async =>
      ScheduleSuggestion.fromJson(
        await _client.post('schedule/generate', body: request.toJson()) as Json,
      );

  @override
  Future<List<CalendarEvent>> apply(
    String suggestionId, {
    List<int>? blockIndexes,
    bool syncToGoogle = false,
  }) async {
    final body = await _client.post(
      'schedule/apply',
      body: {
        'suggestion_id': suggestionId,
        'block_indexes': blockIndexes,
        'sync_to_google': syncToGoogle,
      },
    ) as Json;
    return parseList(body['events'], CalendarEvent.fromJson);
  }
}
