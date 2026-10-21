import '../api/api_client.dart';
import '../models/models.dart';

/// U1–U3.
abstract interface class UserRepository {
  Future<User> getMe();

  Future<User> updateMe(UserUpdate update);

  /// Deletes the account and all its data.
  Future<void> deleteMe();
}

class ApiUserRepository implements UserRepository {
  ApiUserRepository(this._client);

  final ApiClient _client;

  @override
  Future<User> getMe() async =>
      User.fromJson(await _client.get('users/me') as Json);

  @override
  Future<User> updateMe(UserUpdate update) async => User.fromJson(
    await _client.patch('users/me', body: update.toJson()) as Json,
  );

  @override
  Future<void> deleteMe() => _client.delete('users/me');
}
