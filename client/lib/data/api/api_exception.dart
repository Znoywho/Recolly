/// Error raised by the API layer (and by mock repositories, so screens can
/// handle both the same way).
///
/// Backend errors follow `docs/api-v1.md`: `{ "detail": "...", "code": "..." }`.
/// Network failures (no connection, timeout) have [statusCode] == null.
class ApiException implements Exception {
  const ApiException({this.statusCode, this.code, required this.message});

  /// Failure before an HTTP response arrived (offline, DNS, timeout).
  const ApiException.network(this.message)
    : statusCode = null,
      code = 'NETWORK_ERROR';

  /// Builds an exception from an error response body (already JSON-decoded).
  factory ApiException.fromResponse(int statusCode, Object? body) {
    String? code;
    var message = 'HTTP $statusCode';
    if (body is Map<String, Object?>) {
      code = body['code'] as String?;
      final detail = body['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        // FastAPI 422 validation body: [{ "loc": [...], "msg": "...", ... }]
        message = detail
            .whereType<Map<String, Object?>>()
            .map((e) => e['msg'])
            .whereType<String>()
            .join('; ');
        code ??= 'VALIDATION_ERROR';
      }
    }
    return ApiException(statusCode: statusCode, code: code, message: message);
  }

  final int? statusCode;

  /// Machine-readable code such as `TODO_NOT_FOUND`, `OCR_NO_TABLE_FOUND`.
  final String? code;

  /// Human-readable detail from the server (English, not for direct display).
  final String message;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isValidationError => statusCode == 422;
  bool get isServiceUnavailable => statusCode == 503;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
