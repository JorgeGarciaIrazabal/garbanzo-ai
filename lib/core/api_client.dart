import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
/// and JSON encoding for all API calls.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _token;

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

  /// Resolve an API path to a full [Uri].
  Uri uri(String path, {Map<String, String>? queryParameters}) {
    final base = _resolveBaseUrl();
    final p = path.startsWith('/') ? path : '/$path';
    Uri result;
    if (base.isEmpty) {
      result = Uri.base.resolve(p);
    } else {
      result = Uri.parse('$base$p');
    }
    if (queryParameters != null) {
      result = result.replace(queryParameters: queryParameters);
    }
    return result;
  }

  Future<Map<String, String>> _authHeaders({bool withAuth = true}) async {
    final token = withAuth ? await getToken() : null;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(
    String path, {
    bool withAuth = true,
    Map<String, String>? queryParameters,
  }) async {
    return http.get(
      uri(path, queryParameters: queryParameters),
      headers: await _authHeaders(withAuth: withAuth),
    );
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = false,
  }) async {
    return http.post(
      uri(path),
      headers: {
        'Content-Type': 'application/json',
        ...await _authHeaders(withAuth: withAuth),
      },
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    return http.patch(
      uri(path),
      headers: {
        'Content-Type': 'application/json',
        ...await _authHeaders(withAuth: withAuth),
      },
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> delete(
    String path, {
    bool withAuth = true,
  }) async {
    return http.delete(
      uri(path),
      headers: await _authHeaders(withAuth: withAuth),
    );
  }

  /// Send a streaming request. Returns the [http.StreamedResponse] for
  /// callers that need to process the response body as a byte stream (e.g. SSE).
  Future<http.StreamedResponse> send(
    http.Request request, {
    bool withAuth = true,
  }) async {
    final headers = await _authHeaders(withAuth: withAuth);
    request.headers.addAll(headers);
    return request.send();
  }
}
