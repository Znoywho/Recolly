import 'dart:convert';
import 'dart:typed_data';

import 'package:client/data/data.dart';

/// Records requests and answers them from a handler.
class FakeTransport implements HttpTransport {
  FakeTransport(this.handler);

  ApiResponse Function(ApiRequest request) handler;
  final List<ApiRequest> requests = [];

  ApiRequest get last => requests.last;

  Object? get lastJsonBody =>
      last.body == null ? null : jsonDecode(utf8.decode(last.body!));

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}

ApiResponse jsonResponse(int status, Object? body) => ApiResponse(
  status,
  body == null
      ? Uint8List(0)
      : Uint8List.fromList(utf8.encode(jsonEncode(body))),
);
