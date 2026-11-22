/// Build-time configuration for the data layer.
///
/// ```
/// flutter run --dart-define=USE_MOCK_API=false \
///   --dart-define=API_BASE_URL=http://10.0.2.2:8765/api/v1
/// ```
class ApiConfig {
  const ApiConfig._();

  /// `10.0.2.2` is the host machine as seen from the Android emulator.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8765/api/v1',
  );

  /// Mock repositories are the default until the backend endpoints exist.
  static const useMock = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: true,
  );

  /// Web OAuth client ID of the backend, used by google_sign_in to get a
  /// `serverAuthCode`. Pass it with --dart-define=GOOGLE_SERVER_CLIENT_ID=...
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
}
