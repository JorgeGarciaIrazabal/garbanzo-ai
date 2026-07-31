/// Extracts a concise error reason from the response shapes used by FastAPI.
///
/// Most endpoints return `{ "detail": "..." }`. Validation failures may use
/// a list of detail objects, in which case the first human-readable message is
/// returned. The result is intended for diagnostics; callers decide whether a
/// server-provided detail is appropriate to show directly to a user.
String? apiErrorDetail(Object? data) {
  if (data is Map) {
    return _detailValue(data['detail'] ?? data['message'] ?? data['error']);
  }
  if (data is String) {
    final value = data.trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

String? _detailValue(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is List) {
    for (final item in value) {
      if (item is Map) {
        final detail = _detailValue(item['msg'] ?? item['detail']);
        if (detail != null) return detail;
      } else {
        final detail = _detailValue(item);
        if (detail != null) return detail;
      }
    }
  }
  return null;
}

/// HTTP failure with the backend-provided reason retained for diagnostics.
class ApiResponseException implements Exception {
  const ApiResponseException({
    required this.statusCode,
    required this.operation,
    this.detail,
  });

  final int statusCode;
  final String operation;
  final String? detail;

  @override
  String toString() {
    final reason = detail?.trim();
    return 'API Error ($statusCode): '
        '${reason == null || reason.isEmpty ? operation : reason}';
  }
}
