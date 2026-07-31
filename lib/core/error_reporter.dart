import 'dart:async';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/core/platform_info.dart';

typedef ErrorReportSubmitter =
    Future<void> Function(Map<String, dynamic> payload);

/// Session-scoped, best-effort capture of errors that escaped normal UI flows.
///
/// This intentionally uses a bare Dio for submission: the main [ApiClient]'s
/// error interceptor is itself a reporting source, so routing this POST back
/// through it could recurse when the network is unavailable.
class ErrorReporter {
  ErrorReporter({
    ErrorReportSubmitter? submit,
    Future<String> Function()? appVersion,
  }) : _submit = submit,
       _appVersion = appVersion;

  static final ErrorReporter instance = ErrorReporter();

  final ErrorReportSubmitter? _submit;
  final Future<String> Function()? _appVersion;
  final Set<String> _fingerprints = {};
  Map<String, dynamic> _context = const {};
  bool _isReporting = false;

  /// Called by chat/room state as navigation changes; read only when an error
  /// arrives so global Flutter callbacks retain the latest active context.
  void setContext({
    String? conversationId,
    String? messageId,
    Map<String, dynamic> context = const {},
  }) {
    _context = {
      'conversation_id': ?conversationId,
      'message_id': ?messageId,
      ...context,
    };
  }

  void clearContext() => _context = const {};

  Future<void> report(
    Object error,
    StackTrace stack, {
    String? conversationId,
    String? messageId,
    Map<String, dynamic> context = const {},
  }) async {
    final trace = stack.toString();
    final fingerprint = '${error.runtimeType}:$error\n$trace'.hashCode
        .toString();
    if (_isReporting || !_fingerprints.add(fingerprint)) return;

    _isReporting = true;
    try {
      final version = await _version();
      final reportContext = {
        ..._context,
        'conversation_id': ?conversationId,
        'message_id': ?messageId,
        ...context,
      };
      final platform = PlatformInfo.classification;
      final payload = <String, dynamic>{
        'type': 'bug',
        'title': _title(error),
        'description': _description(
          error,
          trace,
          platform,
          version,
          reportContext,
        ),
        'conversation_id': reportContext['conversation_id'],
        'severity': 'error',
        'source': 'frontend',
        'metadata': {
          'error': '$error',
          'stack_trace': trace.length > 10000
              ? trace.substring(0, 10000)
              : trace,
          'platform': platform,
          'app_version': version,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'context': reportContext,
          ...reportContext,
        },
      };
      await (_submit ?? _post)(payload);
    } catch (_) {
      // Reporting must never turn the original exception into a second one.
    } finally {
      _isReporting = false;
    }
  }

  Future<void> reportNetworkError(DioException error) => report(
    error,
    error.stackTrace,
    context: {
      'network': {
        'method': error.requestOptions.method,
        'url': error.requestOptions.uri.toString(),
        'status_code': error.response?.statusCode,
        'response_body': _truncate('${error.response?.data ?? ''}', 4000),
      },
    },
  );

  Future<String> _version() async {
    if (_appVersion != null) return _appVersion();
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _post(Map<String, dynamic> payload) async {
    final token = await ApiClient.instance.getToken();
    if (token == null || token.isEmpty) return;
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiClient.instance.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        contentType: 'application/json',
        validateStatus: (_) => true,
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    await dio.post('/api/v1/reports', data: payload);
  }

  String _title(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final detail = apiErrorDetail(error.response?.data);
      if (status != null && detail != null) {
        return _truncate('Backend error ($status): $detail', 200);
      }
    }
    final oneLine = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _truncate('Frontend error: ${error.runtimeType}: $oneLine', 200);
  }

  String _description(
    Object error,
    String trace,
    String platform,
    String version,
    Map<String, dynamic> context,
  ) => _truncate(
    'Error: $error\nPlatform: $platform\nApp version: $version\n'
    'Context: $context\n\n$trace',
    10000,
  );

  String _truncate(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);
}
