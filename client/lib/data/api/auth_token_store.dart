import '../models/auth.dart';

/// Holds the backend JWTs in memory so [ApiClient] can send the bearer token.
///
/// Refreshing on expiry and persisting across restarts are part of R07.
class AuthTokenStore {
  AuthTokenStore([this._tokens]);

  AuthTokens? _tokens;

  AuthTokens? get tokens => _tokens;
  String? get accessToken => _tokens?.accessToken;

  void save(AuthTokens tokens) => _tokens = tokens;

  void clear() => _tokens = null;
}
