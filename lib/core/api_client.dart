import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

String _resolveBaseUrl() {
  if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
  if (kDebugMode) return 'http://127.0.0.1:8000';
  return '';
}

const _tokenKey = 'auth_token';

/// Centralized HTTP client that handles base URL resolution, auth headers,
/// and JSON encoding for all API calls using Dio.
///
/// Token lifecycle: the auth token is read from SharedPreferences exactly
/// once at startup (via [_tokenReady]). After that, [_token] is the sole
/// source of truth. [setToken] updates both in-memory and prefs. This avoids
/// a race where a stale token could be re-read from prefs between a
/// [setToken] clear and its pending prefs.remove() flushing to disk.
class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: _resolveBaseUrl(),
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
      // Don't throw on non-2xx so callers can inspect status codes directly.
      validateStatus: (status) => true,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
    ));

    _tokenReady = _hydrateTokenFromPrefs();
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  String? _token;
  late final Future<void> _tokenReady;

  String get baseUrl => _dio.options.baseUrl;

  /// Callback invoked when a 401 is received on an authenticated request.
  /// Set this from your app to trigger navigation to the login screen.
  VoidCallback? onUnauthorized;

  Future<void> _hydrateTokenFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
    } catch (_) {
      // If prefs fails, start with no token — user will log in.
    }
  }

  /// Returns the current auth token, waiting for the initial prefs load on
  /// first call. After that, returns the in-memory value synchronously.
  Future<String?> getToken() async {
    await _tokenReady;
    return _token;
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString(_tokenKey, token);
    } else {
      await prefs.remove(_tokenKey);
    }
  }

  /// Ensures the startup token-load has completed. Prefer callers to await
  /// this during app bootstrap so the first request's interceptor doesn't
  /// have to block on prefs I/O.
  Future<void> loadToken() => _tokenReady;

  // ---------------------------------------------------------------------------
  // Interceptors
  // ---------------------------------------------------------------------------

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    if (options.uri.host.contains('ngrok')) {
      options.headers['ngrok-skip-browser-warning'] = 'true';
    }
    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.statusCode == 401 && _token != null) {
      // Fire-and-forget is fine here: in-memory _token is cleared
      // synchronously inside setToken, which is what matters for
      // subsequent interceptor reads. The prefs write flushes later.
      setToken(null);
      onUnauthorized?.call();
    }
    handler.next(response);
  }

  // ---------------------------------------------------------------------------
  // Convenience HTTP methods
  // ---------------------------------------------------------------------------

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(
    String path, {
    Object? data,
  }) {
    return _dio.post(path, data: data);
  }

  Future<Response> patch(
    String path, {
    Object? data,
  }) {
    return _dio.patch(path, data: data);
  }

  Future<Response> put(
    String path, {
    Object? data,
  }) {
    return _dio.put(path, data: data);
  }

  Future<Response> delete(String path, {Object? data}) {
    return _dio.delete(path, data: data);
  }

  /// Send a POST request expecting an SSE stream response.
  Future<Response> streamPost(
    String path, {
    Object? data,
  }) {
    return _dio.post(
      path,
      data: data,
      options: Options(
        headers: {'Accept': 'text/event-stream'},
        responseType: ResponseType.stream,
      ),
    );
  }

  /// Send a POST request with multipart form data.
  Future<Response> postMultipart(
    String path, {
    required FormData data,
  }) {
    return _dio.post(path, data: data);
  }

  /// Send a POST request expecting binary response data.
  Future<Response<List<int>>> postBytes(
    String path, {
    Object? data,
    Duration? receiveTimeout,
  }) {
    return _dio.post<List<int>>(
      path,
      data: data,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: receiveTimeout,
      ),
    );
  }

  /// Send a POST request expecting a streaming binary response.
  Future<Response<ResponseBody>> postStreamBytes(
    String path, {
    Object? data,
  }) {
    return _dio.post<ResponseBody>(
      path,
      data: data,
      options: Options(responseType: ResponseType.stream),
    );
  }
}
