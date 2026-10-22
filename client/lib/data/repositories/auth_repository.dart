import '../api/api_client.dart';
import '../models/models.dart';

/// Backend session (A1–A3). Google sign-in UI itself is R07.
abstract interface class AuthRepository {
  /// Exchanges the `serverAuthCode` from `google_sign_in` for backend JWTs
  /// and stores them for later requests.
  Future<AuthSession> signInWithGoogle(String serverAuthCode);

  /// Rotates the refresh token.
  Future<AuthTokens> refresh(String refreshToken);

  /// Revokes the refresh token and forgets the stored tokens.
  Future<void> logout();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<AuthSession> signInWithGoogle(String serverAuthCode) async {
    final body = await _client.post(
      'auth/google',
      body: {'server_auth_code': serverAuthCode},
      auth: false,
    );
    final session = AuthSession.fromJson(body as Json);
    _client.tokenStore.save(session.tokens);
    return session;
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    final body = await _client.post(
      'auth/refresh',
      body: {'refresh_token': refreshToken},
      auth: false,
    );
    return AuthTokens.fromJson(body as Json);
  }

  @override
  Future<void> logout() async {
    final refreshToken = _client.tokenStore.tokens?.refreshToken;
    try {
      if (refreshToken != null) {
        await _client.post(
          'auth/logout',
          body: {'refresh_token': refreshToken},
        );
      }
    } finally {
      _client.tokenStore.clear();
    }
  }
}
