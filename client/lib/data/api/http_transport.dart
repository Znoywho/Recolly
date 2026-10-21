import 'dart:io';
import 'dart:typed_data';

import 'api_exception.dart';

/// A raw HTTP request built by [ApiClient].
class ApiRequest {
  const ApiRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List? body;
}

/// A raw HTTP response.
class ApiResponse {
  const ApiResponse(this.statusCode, this.body);

  final int statusCode;
  final Uint8List body;
}

/// Sends raw HTTP requests. Swappable so tests can run without a network.
abstract interface class HttpTransport {
  Future<ApiResponse> send(ApiRequest request);

  void close();
}

/// [HttpTransport] backed by `dart:io` (Android target), so the data layer
/// needs no extra package.
class IoHttpTransport implements HttpTransport {
  IoHttpTransport([HttpClient? client]) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    try {
      final req = await _client.openUrl(request.method, request.uri);
      request.headers.forEach(req.headers.set);
      final body = request.body;
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return ApiResponse(res.statusCode, builder.takeBytes());
    } on IOException catch (e) {
      throw ApiException.network(e.toString());
    }
  }

  @override
  void close() => _client.close();
}
