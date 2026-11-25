import '../models/auth.dart';

/// Holds the backend JWTs in memory so [ApiClient] can send the bearer token.
///
/// [onChanged] lets the app persist every change (sign-in, refresh rotation,
/// logout) so the login survives app restarts.
class AuthTokenStore {
  AuthTokenStore([this._tokens]);

  AuthTokens? _tokens;

  /// Called after every [save] / [clear] with the new value (null = cleared).
  void Function(AuthTokens? tokens)? onChanged;

  /// Called by [ApiClient] when the server rejects the refresh token, so the
  /// app can send the user back to login (a normal logout does not call it).
  void Function()? onExpired;

  AuthTokens? get tokens => _tokens;
  String? get accessToken => _tokens?.accessToken;

  /// Stores new tokens and notifies [onChanged].
  void save(AuthTokens tokens) {
    _tokens = tokens;
    onChanged?.call(tokens);
  }

  /// Forgets the tokens and notifies [onChanged].
  void clear() {
    _tokens = null;
    onChanged?.call(null);
  }
}
