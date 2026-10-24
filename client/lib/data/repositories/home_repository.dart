import '../api/api_client.dart';
import '../models/models.dart';

/// Home screen overview (O1).
abstract interface class HomeRepository {
  /// Throws `ApiException` 404 `HEALTH_PROFILE_NOT_FOUND` before onboarding.
  Future<HomeOverview> getOverview();
}

class ApiHomeRepository implements HomeRepository {
  ApiHomeRepository(this._client);

  final ApiClient _client;

  @override
  Future<HomeOverview> getOverview() async =>
      HomeOverview.fromJson(await _client.get('home') as Json);
}
