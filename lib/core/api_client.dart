import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/core/http_adapter/http_adapter_stub.dart'
    if (dart.library.js_interop) 'package:garbanzo_ai/core/http_adapter/http_adapter_web.dart';

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
const _refreshTokenKey = 'auth_refresh_token';

/// Centralized HTTP client that handles base URL resolution, auth headers,
/// and JSON encoding for all API calls using Dio.
///
/// Token lifecycle: the auth tokens are read from SharedPreferences exactly
/// once at startup (via [_tokenReady]). After that, [_token] / [_refreshToken]
/// are the sole source of truth. [setToken] / [setRefreshToken] update both
/// in-memory and prefs. This avoids a race where a stale token could be
/// re-read from prefs between a setter clear and its pending prefs.remove()
/// flushing to disk.
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

    // On web, replace the default XHR adapter with a Fetch-based one so
    // streamed responses (SSE chat, streaming TTS) arrive incrementally.
    // XHR also treats connect+receive timeouts as a TOTAL request deadline,
    // which aborted slow LLM turns; fetch has no such cap. No-op on IO
    // platforms (returns null).
    final platformAdapter = createPlatformAdapter();
    if (platformAdapter != null) {
      _dio.httpClientAdapter = platformAdapter;
    }

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
    ));

    _tokenReady = _hydrateTokenFromPrefs();
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  String? _token;
  String? _refreshToken;
  late final Future<void> _tokenReady;

  /// De-duplicates concurrent refresh attempts: the first 401 kicks off the
  /// refresh, every other in-flight request awaits the same future.
  Future<bool>? _refreshInFlight;

  String get baseUrl => _dio.options.baseUrl;

  /// Compute a WebSocket URL for the given API path.
  /// Converts http(s) base → ws(s), preserving host and path.
  /// Falls back to a local default if base URL is empty (e.g. web release on
  /// origin itself).
  Uri wsUri(String path, {Map<String, String>? queryParameters}) {
    var base = baseUrl;
    if (base.isEmpty) {
      base = Uri.base.toString();
    }
    final uri = Uri.parse(base);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
      queryParameters: queryParameters,
    );
  }

  /// Callback invoked when a 401 is received on an authenticated request.
  /// Set this from your app to trigger navigation to the login screen.
  VoidCallback? onUnauthorized;

  Future<void> _hydrateTokenFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      _refreshToken = prefs.getString(_refreshTokenKey);
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

  Future<String?> getRefreshToken() async {
    await _tokenReady;
    return _refreshToken;
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

  Future<void> setRefreshToken(String? token) async {
    _refreshToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString(_refreshTokenKey, token);
    } else {
      await prefs.remove(_refreshTokenKey);
    }
  }

  /// Set both tokens together. Use this on login/refresh so callers don't
  /// have to remember to persist both.
  Future<void> setTokens({
    required String? accessToken,
    required String? refreshToken,
  }) async {
    await setToken(accessToken);
    await setRefreshToken(refreshToken);
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

  Future<void> _onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    if (response.statusCode != 401 || _token == null) {
      return handler.next(response);
    }

    final original = response.requestOptions;

    // Don't try to refresh when the refresh call itself 401s — that means the
    // refresh token is dead and the user must log in again.
    if (original.path.contains('/api/v1/auth/refresh')) {
      await _clearAuthAndNotify();
      return handler.next(response);
    }

    // Avoid infinite retry loops: each request is retried at most once.
    if (original.extra['__auth_retried__'] == true) {
      await _clearAuthAndNotify();
      return handler.next(response);
    }

    final refreshed = await _attemptRefresh();
    if (!refreshed) {
      await _clearAuthAndNotify();
      return handler.next(response);
    }

    // Re-issue the request with the new token. Mark it so we don't recurse.
    original.extra['__auth_retried__'] = true;
    original.headers['Authorization'] = 'Bearer $_token';
    try {
      final retry = await _dio.fetch(original);
      return handler.resolve(retry);
    } catch (_) {
      return handler.next(response);
    }
  }

  Future<bool> _attemptRefresh() {
    // Coalesce concurrent refresh attempts — many pending requests seeing
    // 401 at once should still produce exactly one network call.
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      // Bypass interceptors: hit the endpoint via a bare Dio instance so a
      // 401 here doesn't re-enter _onResponse and start another refresh.
      final bare = Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        contentType: 'application/json',
        validateStatus: (s) => true,
      ));
      final res = await bare.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      if (res.statusCode != 200 || res.data is! Map<String, dynamic>) {
        return false;
      }
      final data = res.data as Map<String, dynamic>;
      final newAccess = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      if (newAccess == null) return false;
      await setTokens(
        accessToken: newAccess,
        refreshToken: newRefresh ?? refreshToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearAuthAndNotify() async {
    await setTokens(accessToken: null, refreshToken: null);
    onUnauthorized?.call();
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
        // In Dio 5, receiveTimeout caps the gap between successive bytes.
        // Slow local models can pause for >30s while loading or thinking,
        // so we lift the cap (Duration.zero disables it).
        receiveTimeout: Duration.zero,
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
