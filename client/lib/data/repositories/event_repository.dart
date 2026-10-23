import '../api/api_client.dart';
import '../models/models.dart';

/// Calendar events (E1–E5).
abstract interface class EventRepository {
  /// E1: events in `[from, to)` (max 62 days), sorted by start, with
  /// recurring events expanded into instances.
  Future<List<CalendarEvent>> listEvents({
    required DateTime from,
    required DateTime to,
    EventKind? kind,
    EventSource? source,
  });

  Future<CalendarEvent> createEvent(EventCreate event);

  Future<CalendarEvent> getEvent(String id);

  Future<CalendarEvent> updateEvent(String id, EventUpdate update);

  Future<void> deleteEvent(String id);
}

class ApiEventRepository implements EventRepository {
  ApiEventRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<CalendarEvent>> listEvents({
    required DateTime from,
    required DateTime to,
    EventKind? kind,
    EventSource? source,
  }) async {
    final body = await _client.get(
      'events',
      query: {
        'from': formatDateTime(from),
        'to': formatDateTime(to),
        'kind': kind?.value,
        'source': source?.value,
      },
    );
    return parseItems(body, CalendarEvent.fromJson);
  }

  @override
  Future<CalendarEvent> createEvent(EventCreate event) async =>
      CalendarEvent.fromJson(
        await _client.post('events', body: event.toJson()) as Json,
      );

  @override
  Future<CalendarEvent> getEvent(String id) async =>
      CalendarEvent.fromJson(await _client.get('events/$id') as Json);

  @override
  Future<CalendarEvent> updateEvent(String id, EventUpdate update) async =>
      CalendarEvent.fromJson(
        await _client.patch('events/$id', body: update.toJson()) as Json,
      );

  @override
  Future<void> deleteEvent(String id) => _client.delete('events/$id');
}
