import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/models.dart';

/// Chronotype questionnaire, health profile, sleep logs, sleep debt and
/// biorhythm (C1, H1–H8). Endpoints marked "later" in the contract (H9,
/// screen inference, KSS check-ins, model B1/B2) are not wrapped yet.
abstract interface class SleepRepository {
  /// C1: scores the onboarding questionnaire without saving it. Throws
  /// `ApiException` 422 `RMEQ_REQUIRED` when MCTQ cannot be used.
  Future<ChronotypeAssessment> assessChronotype(
    ChronotypeAssessmentRequest request,
  );

  /// `null` if onboarding is not finished (H1 returns 404).
  Future<HealthProfile?> getHealthProfile();

  Future<HealthProfile> saveHealthProfile(HealthProfileInput profile);

  /// H3: logs whose wake-up date is in [from]..[to] (default: last 14 days),
  /// newest first. [confirmed] `false` → only inferred logs to confirm.
  Future<List<SleepLog>> listSleepLogs({
    DateTime? from,
    DateTime? to,
    SleepSource? source,
    bool? confirmed,
  });

  Future<SleepLog> createSleepLog(SleepLogCreate log);

  Future<SleepLog> updateSleepLog(String id, SleepLogUpdate update);

  Future<void> deleteSleepLog(String id);

  /// H7: [days] 1–30, ending today.
  Future<SleepDebt> getSleepDebt({int days = 7});

  /// H8: [days] 1–7 starting at [date] (default today), sampled every
  /// [intervalMinutes] (5, 15, 30 or 60; default 15).
  Future<Biorhythm> getBiorhythm({
    DateTime? date,
    int? days,
    int? intervalMinutes,
  });
}

class ApiSleepRepository implements SleepRepository {
  ApiSleepRepository(this._client);

  final ApiClient _client;

  @override
  Future<ChronotypeAssessment> assessChronotype(
    ChronotypeAssessmentRequest request,
  ) async => ChronotypeAssessment.fromJson(
    await _client.post('chronotype/assess', body: request.toJson()) as Json,
  );

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
  Future<HealthProfile> saveHealthProfile(HealthProfileInput profile) async =>
      HealthProfile.fromJson(
        await _client.put('health-profile', body: profile.toJson()) as Json,
      );

  @override
  Future<List<SleepLog>> listSleepLogs({
    DateTime? from,
    DateTime? to,
    SleepSource? source,
    bool? confirmed,
  }) async {
    final body = await _client.get(
      'sleep-logs',
      query: {
        'from': formatDateOrNull(from),
        'to': formatDateOrNull(to),
        'source': source?.value,
        'confirmed': confirmed,
      },
    );
    return parseItems(body, SleepLog.fromJson);
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
  Future<Biorhythm> getBiorhythm({
    DateTime? date,
    int? days,
    int? intervalMinutes,
  }) async => Biorhythm.fromJson(
    await _client.get(
      'biorhythm',
      query: {
        'date': formatDateOrNull(date),
        'days': days,
        'interval_minutes': intervalMinutes,
      },
    ) as Json,
  );
}
