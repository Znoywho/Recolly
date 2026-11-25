import 'package:client/data/data.dart';

// R46: two-way sync conflicts are solved without asking the user.
// Rule lives here only: keep the version edited last.
ConflictResolution pickSide(SyncConflict c) =>
    c.google.updatedAt.isAfter(c.local.updatedAt)
    ? ConflictResolution.google
    : ConflictResolution.local;

// Returns how many conflicts were resolved. One failure does not stop the rest.
Future<int> resolveAllConflicts(CalendarSyncRepository repo) async {
  final conflicts = await repo.listConflicts();
  var done = 0;
  for (final c in conflicts) {
    try {
      await repo.resolveConflict(c.id, pickSide(c));
      done++;
    } catch (_) {}
  }
  return done;
}
