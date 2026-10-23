import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'api_exception.dart';
import 'auth_token_store.dart';
import 'http_transport.dart';

/// Thin JSON client for the Recolly REST API (`docs/api-v1.md`).
///
/// - Paths are relative to [baseUri], e.g. `get('todos')`.
/// - Adds `Authorization: Bearer <token>` unless `auth: false`.
/// - Non-2xx responses and network failures throw [ApiException].
/// - Returns the decoded JSON body, or `null` for empty bodies (204).
class ApiClient {
  ApiClient({
    required String baseUrl,
    HttpTransport? transport,
    AuthTokenStore? tokenStore,
    this.timeout = const Duration(seconds: 30),
  }) : baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _transport = transport ?? IoHttpTransport(),
       tokenStore = tokenStore ?? AuthTokenStore();

  final Uri baseUri;
  final AuthTokenStore tokenStore;
  final Duration timeout;
  final HttpTransport _transport;

  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool auth = true,
  }) => _send('GET', path, query: query, auth: auth);

  Future<Object?> post(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool auth = true,
  }) => _sendJson('POST', path, body, query: query, auth: auth);

  Future<Object?> put(String path, {Object? body, bool auth = true}) =>
      _sendJson('PUT', path, body, auth: auth);

  Future<Object?> patch(String path, {Object? body, bool auth = true}) =>
      _sendJson('PATCH', path, body, auth: auth);

  Future<Object?> delete(String path, {Object? body, bool auth = true}) =>
      _sendJson('DELETE', path, body, auth: auth);

  /// Uploads one file as `multipart/form-data` (OCR photo, voice recording),
  /// with optional text [fields] sent before it.
  Future<Object?> postMultipart(
    String path, {
    required String field,
    required Uint8List bytes,
    required String filename,
    String? contentType,
    Map<String, String> fields = const {},
    bool auth = true,
  }) {
    final boundary = 'recolly-${_randomHex(16)}';
    final safeName = filename.replaceAll('"', '%22');
    final type = contentType ?? guessContentType(filename);
    final body = BytesBuilder(copy: false);
    for (final e in fields.entries) {
      body.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="${e.key}"\r\n\r\n'
          '${e.value}\r\n',
        ),
      );
    }
    body
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="$field"; '
          'filename="$safeName"\r\n'
          'Content-Type: $type\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    return _send(
      'POST',
      path,
      body: body.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
      auth: auth,
    );
  }

  void close() => _transport.close();

  Uri resolve(String path, [Map<String, Object?>? query]) {
    final uri = baseUri.resolve(
      path.startsWith('/') ? path.substring(1) : path,
    );
    // A list value repeats the key (`?status=todo&status=in_progress`).
    final params = <String, Object>{
      for (final e in (query ?? const {}).entries)
        if (e.value case final List<Object?> list when list.isNotEmpty)
          e.key: [for (final v in list) v.toString()]
        else if (e.value != null && e.value is! List)
          e.key: e.value.toString(),
    };
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  Future<Object?> _sendJson(
    String method,
    String path,
    Object? body, {
    Map<String, Object?>? query,
    required bool auth,
  }) {
    return _send(
      method,
      path,
      query: query,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      contentType: body == null ? null : 'application/json',
      auth: auth,
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Uint8List? body,
    String? contentType,
    required bool auth,
  }) async {
    final uri = resolve(path, query);
    final token = auth ? tokenStore.accessToken : null;
    final request = ApiRequest(
      method: method,
      uri: uri,
      headers: {
        'accept': 'application/json',
        'content-type': ?contentType,
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body,
    );
    final ApiResponse response;
    try {
      response = await _transport.send(request).timeout(timeout);
    } on TimeoutException {
      throw ApiException.network('Request to $uri timed out');
    }
    return _decode(response);
  }

  Object? _decode(ApiResponse response) {
    Object? json;
    if (response.body.isNotEmpty) {
      final text = utf8.decode(response.body, allowMalformed: true);
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = {'detail': text};
      }
    }
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) throw ApiException.fromResponse(response.statusCode, json);
    return json;
  }

  static final _random = Random.secure();

  static String _randomHex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// MIME type for the upload formats listed in `docs/api-v1.md`.
String guessContentType(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'heic' => 'image/heic',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    _ => 'application/octet-stream',
  };
}
