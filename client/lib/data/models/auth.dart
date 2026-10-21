import 'json_utils.dart';
import 'user.dart';

/// Backend JWT pair (A1 / A2 response).
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'bearer',
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Json json) => AuthTokens(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    tokenType: json['token_type'] as String? ?? 'bearer',
    expiresIn: json['expires_in'] as int,
  );

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  /// Access token lifetime in seconds.
  final int expiresIn;

  Json toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
    'expires_in': expiresIn,
  };
}

/// A1 `POST /auth/google` response.
class AuthSession {
  const AuthSession({
    required this.tokens,
    required this.user,
    required this.isNewUser,
  });

  factory AuthSession.fromJson(Json json) => AuthSession(
    tokens: AuthTokens.fromJson(json),
    user: User.fromJson(json['user'] as Json),
    isNewUser: json['is_new_user'] as bool,
  );

  final AuthTokens tokens;
  final User user;

  /// `true` → show onboarding / sleep profile (R55).
  final bool isNewUser;

  Json toJson() => {
    ...tokens.toJson(),
    'user': user.toJson(),
    'is_new_user': isNewUser,
  };
}
