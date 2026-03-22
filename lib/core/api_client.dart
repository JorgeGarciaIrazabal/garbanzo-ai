import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

String _resolveBaseUrl() {
  if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
  if (kDebugMode) return 'http://localhost:8000';
  return '';
}

const _tokenKey = 'auth_token';

/// Centralized HTTP client that handles base URL resolution, auth headers,
/// and JSON encoding for all API calls using Dio.
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
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  String? _token;

  /// Callback invoked when a 401 is received on an authenticated request.
  /// Set this from your app to trigger navigation to the login screen.
  VoidCallback? onUnauthorized;

  Future<String?> getToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
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

  Future<void> loadToken() async {
    _token ??= await getToken();
  }

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
    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.statusCode == 401 && _token != null) {
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

  Future<Response> delete(String path) {
    return _dio.delete(path);
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
