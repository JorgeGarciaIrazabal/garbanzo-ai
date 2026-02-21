import 'dart:convert';

import 'api_client.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _client = ApiClient.instance;

  Future<AuthResult> register(
    String email,
    String password, {
    String? fullName,
  }) async {
    final res = await _client.post(
      '/api/v1/auth/register',
      body: {
        'email': email.trim(),
        'password': password,
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
      },
    );

    if (res.statusCode == 201) {
      // Auto-login after registration
      return await login(email, password);
    }

    if (res.statusCode == 400) {
      final json = jsonDecode(res.body) as Map<String, dynamic>?;
      final detail = json?['detail'] as String?;
      return AuthResult.failure(detail ?? 'Registration failed');
    }
    return AuthResult.failure('Registration failed. Please try again.');
  }

  Future<AuthResult> login(String email, String password) async {
    final res = await _client.post(
      '/api/v1/auth/login',
      body: {'email': email.trim(), 'password': password},
    );

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final token = json['access_token'] as String?;
      if (token != null) {
        await _client.setToken(token);
        return AuthResult.success();
      }
    }

    if (res.statusCode == 401) {
      return AuthResult.failure('Incorrect email or password');
    }
    return AuthResult.failure('Login failed. Please try again.');
  }

  Future<void> logout() async {
    await _client.setToken(null);
  }

  Future<bool> isLoggedIn() async {
    final token = await _client.getToken();
    if (token == null) return false;
    final res = await _client.get('/api/v1/auth/me');
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final res = await _client.get('/api/v1/auth/me');
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body) as Map<String, dynamic>?;
  }
}

class AuthResult {
  final bool success;
  final String? error;

  AuthResult._({required this.success, this.error});

  factory AuthResult.success() => AuthResult._(success: true);
  factory AuthResult.failure(String message) => AuthResult._(
        success: false,
        error: message,
      );
}
