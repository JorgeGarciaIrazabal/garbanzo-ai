import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Base URL for API calls. Override with --dart-define=API_BASE_URL=... if needed.
/// In debug mode (flutter run), defaults to http://localhost:8000 (the backend).
/// Otherwise uses relative URLs when the web build is served from the backend.
const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

String _base() {
  if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
  if (kDebugMode) return 'http://localhost:8000';
  return '';
}

const _tokenKey = 'auth_token';

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

  Uri _uri(String path) {
    final base = _base();
    final p = path.startsWith('/') ? path : '/$path';
    if (base.isEmpty) {
      return Uri.base.resolve(p);
    }
    return Uri.parse('$base$p');
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = false,
  }) async {
    final token = withAuth ? await getToken() : null;
    return http.post(
      _uri(path),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> get(String path, {bool withAuth = true}) async {
    final token = withAuth ? await getToken() : null;
    return http.get(
      _uri(path),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
  }
}
