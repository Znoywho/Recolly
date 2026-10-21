import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/models.dart';

/// Health profile, sleep logs, sleep debt and biorhythm (H1–H8).
abstract interface class SleepRepository {
  /// `null` if onboarding is not finished (H1 returns 404).
  Future<HealthProfile?> getHealthProfile();

  Future<HealthProfile> saveHealthProfile(HealthProfile profile);

  Future<Paginated<SleepLog>> listSleepLogs({
    DateTime? from,
    DateTime? to,
    int? limit,
    String? cursor,
  });

  Future<SleepLog> createSleepLog(SleepLogCreate log);

  Future<SleepLog> updateSleepLog(String id, SleepLogUpdate update);

  Future<void> deleteSleepLog(String id);

  Future<SleepDebt> getSleepDebt({int days = 7});

  Future<Biorhythm> getBiorhythm(DateTime date);
}

class ApiSleepRepository implements SleepRepository {
  ApiSleepRepository(this._client);

  final ApiClient _client;

  @override
  Future<HealthProfile?> getHealthProfile() async {
    try {
      return HealthProfile.fromJson(
        await _client.get('health-profile') as Json,
      );
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<HealthProfile> saveHealthProfile(HealthProfile profile) async =>
      HealthProfile.fromJson(
        await _client.put('health-profile', body: profile.toJson()) as Json,
      );

  @override
  Future<Paginated<SleepLog>> listSleepLogs({
    DateTime? from,
    DateTime? to,
    int? limit,
    String? cursor,
  }) async {
    final body = await _client.get(
      'sleep-logs',
      query: {
        'from': formatDateOrNull(from),
        'to': formatDateOrNull(to),
        'limit': limit,
        'cursor': cursor,
      },
    );
    return Paginated.fromJson(body, SleepLog.fromJson);
  }

  @override
  Future<SleepLog> createSleepLog(SleepLogCreate log) async =>
      SleepLog.fromJson(
        await _client.post('sleep-logs', body: log.toJson()) as Json,
      );

  @override
  Future<SleepLog> updateSleepLog(String id, SleepLogUpdate update) async =>
      SleepLog.fromJson(
        await _client.patch('sleep-logs/$id', body: update.toJson()) as Json,
      );

  @override
  Future<void> deleteSleepLog(String id) => _client.delete('sleep-logs/$id');

  @override
  Future<SleepDebt> getSleepDebt({int days = 7}) async => SleepDebt.fromJson(
    await _client.get('sleep-debt', query: {'days': days}) as Json,
  );

  @override
  Future<Biorhythm> getBiorhythm(DateTime date) async => Biorhythm.fromJson(
    await _client.get('biorhythm', query: {'date': formatDate(date)}) as Json,
  );
}
