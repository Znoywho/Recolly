import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:client/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  late FakeTransport transport;
  late ApiClient client;

  setUp(() {
    transport = FakeTransport((_) => jsonResponse(200, {}));
    client = ApiClient(
      baseUrl: 'http://localhost:8765/api/v1',
      transport: transport,
      tokenStore: AuthTokenStore(
        const AuthTokens(
          accessToken: 'old',
          refreshToken: 'r1',
          expiresIn: 900,
        ),
      ),
    );
  });

  test('builds URL, query and headers', () async {
    await client.get(
      'todos',
      query: {'status': 'todo', 'category': null, 'limit': 20},
    );
    final req = transport.last;
    expect(req.method, 'GET');
    expect(
      req.uri.toString(),
      'http://localhost:8765/api/v1/todos?status=todo&limit=20',
    );
    expect(req.headers['authorization'], 'Bearer old');
    expect(req.body, isNull);
  });

  test('public endpoints send no token', () async {
    await client.post(
      'auth/google',
      body: {'server_auth_code': 'c'},
      auth: false,
    );
    expect(transport.last.headers.containsKey('authorization'), isFalse);
    expect(transport.last.headers['content-type'], 'application/json');
    expect(transport.lastJsonBody, {'server_auth_code': 'c'});
  });

  test('204 returns null', () async {
    transport.handler = (_) => jsonResponse(204, null);
    expect(await client.delete('todos/1'), isNull);
  });

  test('maps error body to ApiException', () async {
    transport.handler = (_) => jsonResponse(404, {
      'detail': 'Todo not found',
      'code': 'TODO_NOT_FOUND',
    });
    await expectLater(
      client.get('todos/1'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isNotFound, 'isNotFound', isTrue)
            .having((e) => e.code, 'code', 'TODO_NOT_FOUND')
            .having((e) => e.message, 'message', 'Todo not found'),
      ),
    );
  });

  test('maps FastAPI 422 validation body', () async {
    transport.handler = (_) => jsonResponse(422, {
      'detail': [
        {
          'loc': ['body', 'title'],
          'msg': 'Field required',
          'type': 'missing',
        },
      ],
    });
    await expectLater(
      client.post('todos', body: {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'VALIDATION_ERROR')
            .having((e) => e.message, 'message', 'Field required'),
      ),
    );
  });

  test('401 surfaces as ApiException without retry', () async {
    transport.handler = (_) => jsonResponse(401, {'detail': 'expired'});
    await expectLater(
      client.get('users/me'),
      throwsA(
        isA<ApiException>().having((e) => e.isUnauthorized, '401', isTrue),
      ),
    );
    expect(transport.requests, hasLength(1));
  });

  test('multipart upload', () async {
    await client.postMultipart(
      'ocr/timetable',
      field: 'image',
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'tkb.jpg',
    );
    final req = transport.last;
    final contentType = req.headers['content-type']!;
    expect(contentType, startsWith('multipart/form-data; boundary='));
    final boundary = contentType.split('boundary=').last;
    final body = latin1.decode(req.body!);
    expect(body, startsWith('--$boundary\r\n'));
    expect(body, contains('name="image"; filename="tkb.jpg"'));
    expect(body, contains('Content-Type: image/jpeg\r\n\r\n\x01\x02\x03\r\n'));
    expect(body, endsWith('--$boundary--\r\n'));
  });

  test('timeout becomes a network ApiException', () async {
    final slow = ApiClient(
      baseUrl: 'http://x/api/v1',
      timeout: const Duration(milliseconds: 10),
      transport: _NeverTransport(),
    );
    await expectLater(
      slow.get('health', auth: false),
      throwsA(
        isA<ApiException>().having(
          (e) => e.isNetworkError,
          'isNetworkError',
          isTrue,
        ),
      ),
    );
  });

  test('repositories hit the documented endpoints', () async {
    final repos = AppRepositories.api(client);
    transport.handler = (req) => switch (req.uri.path) {
      '/api/v1/todos' => jsonResponse(200, {'items': [], 'next_cursor': null}),
      '/api/v1/ocr/timetable' => jsonResponse(202, {
        'job_id': 'j',
        'status': 'queued',
      }),
      '/api/v1/health-profile' => jsonResponse(404, {
        'code': 'HEALTH_PROFILE_NOT_FOUND',
      }),
      '/api/v1/schedule/apply' => jsonResponse(201, {'events': []}),
      _ => jsonResponse(204, null),
    };

    final page = await repos.todos.listTodos(
      query: TodoQuery(
        status: TodoStatus.inProgress,
        dueBefore: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(page.items, isEmpty);
    expect(transport.last.uri.queryParameters, {
      'status': 'in_progress',
      'due_before': '2026-11-01T00:00:00.000Z',
    });

    final job = await repos.timetable.uploadTimetablePhoto(
      Uint8List(1),
      filename: 'a.png',
    );
    expect(job.status, JobStatus.queued);

    expect(await repos.sleep.getHealthProfile(), isNull);

    await repos.schedule.apply('s', syncToGoogle: true);
    expect(transport.lastJsonBody, {
      'suggestion_id': 's',
      'block_indexes': null,
      'sync_to_google': true,
    });

    await repos.reminders.unregisterDevice('a:b/c');
    expect(transport.last.method, 'DELETE');
    expect(transport.last.uri.path, '/api/v1/devices/a%3Ab%2Fc');
  });

  test('sign-in stores tokens for later calls', () async {
    final repos = AppRepositories.api(
      ApiClient(baseUrl: 'http://x/api/v1', transport: transport),
    );
    const user = {
      'id': 'u',
      'email': 'e',
      'display_name': 'n',
      'timezone': 'Asia/Ho_Chi_Minh',
      'google_calendar_connected': false,
      'created_at': '2026-10-19T08:00:00+07:00',
    };
    transport.handler = (req) => req.uri.path.endsWith('users/me')
        ? jsonResponse(200, user)
        : jsonResponse(200, {
            'access_token': 'acc',
            'refresh_token': 'ref',
            'token_type': 'bearer',
            'expires_in': 900,
            'user': user,
            'is_new_user': false,
          });
    await repos.auth.signInWithGoogle('code');
    await repos.user.getMe();
    expect(transport.last.headers['authorization'], 'Bearer acc');
  });
}

class _NeverTransport implements HttpTransport {
  @override
  Future<ApiResponse> send(ApiRequest request) =>
      Completer<ApiResponse>().future;

  @override
  void close() {}
}
