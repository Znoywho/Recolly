import 'dart:convert';

import 'package:client/data/data.dart';
import 'package:client/features/auth/auth_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data/fake_transport.dart';

const _user = {
  'id': 'u',
  'email': 'e',
  'display_name': 'n',
  'timezone': 'Asia/Ho_Chi_Minh',
  'google_calendar_connected': false,
  'onboarding_completed': true,
  'created_at': '2026-10-19T08:00:00+07:00',
};

const _savedTokens = AuthTokens(
  accessToken: 'old',
  refreshToken: 'r1',
  expiresIn: 900,
);

ApiResponse _newTokens() => jsonResponse(200, {
  'access_token': 'new',
  'refresh_token': 'r2',
  'expires_in': 900,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  late FakeTransport transport;
  late AuthController controller;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      AuthController.tokenKey: jsonEncode(_savedTokens.toJson()),
    });
    transport = FakeTransport((_) => jsonResponse(200, _user));
    controller = AuthController(
      AppRepositories.api(
        ApiClient(baseUrl: 'http://localhost/api/v1', transport: transport),
      ),
    );
  });

  Future<String?> stored() => storage.read(key: AuthController.tokenKey);

  test('offline at start keeps the saved login', () async {
    transport.handler = (_) => throw const ApiException.network('offline');
    await controller.start();
    expect(controller.status, AuthStatus.loggedIn);
    expect(await stored(), isNotNull);
  });

  test('expired access token is refreshed and the new pair is saved', () async {
    transport.handler = (req) {
      if (req.uri.path.endsWith('auth/refresh')) return _newTokens();
      return req.headers['authorization'] == 'Bearer new'
          ? jsonResponse(200, _user)
          : jsonResponse(401, {'detail': 'expired'});
    };
    await controller.start();
    await pumpEventQueue();
    expect(controller.status, AuthStatus.loggedIn);
    expect(jsonDecode((await stored())!)['refresh_token'], 'r2');
  });

  test('rejected refresh at start logs out without the expiry hook', () async {
    var expired = 0;
    controller.onSessionExpired = () => expired++;
    transport.handler = (_) => jsonResponse(401, {'detail': 'expired'});
    await controller.start();
    await pumpEventQueue();
    expect(controller.status, AuthStatus.loggedOut);
    expect(await stored(), isNull);
    expect(expired, 0);
  });

  test('rejected refresh mid-session sends the user to login once', () async {
    var expired = 0;
    controller.onSessionExpired = () => expired++;
    await controller.start();
    expect(controller.status, AuthStatus.loggedIn);

    transport.handler = (_) => jsonResponse(401, {'detail': 'expired'});
    await expectLater(
      controller.repos.todos.listTodos(),
      throwsA(isA<ApiException>()),
    );
    await pumpEventQueue();
    expect(expired, 1);
    expect(controller.status, AuthStatus.loggedOut);
    expect(await stored(), isNull);
  });
}
