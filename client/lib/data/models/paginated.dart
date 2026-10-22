import 'json_utils.dart';

/// Cursor-paginated list: `{ "items": [...], "next_cursor": "..." | null }`.
class Paginated<T> {
  const Paginated({required this.items, this.nextCursor});

  factory Paginated.fromJson(Object? body, T Function(Json json) fromJson) =>
      Paginated(
        items: parseItems(body, fromJson),
        nextCursor: body is Map ? body['next_cursor'] as String? : null,
      );

  final List<T> items;

  /// Pass as `cursor` to load the next page; `null` → last page.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
