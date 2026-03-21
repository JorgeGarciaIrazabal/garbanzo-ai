import 'package:dio/dio.dart';

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
    try {
      final res = await _client.post(
        '/api/v1/auth/register',
        data: {
          'email': email.trim(),
          'password': password,
          if (fullName != null && fullName.trim().isNotEmpty)
            'full_name': fullName.trim(),
        },
      );

      if (res.statusCode == 201) {
        // Auto-login after registration
        return await login(email, password);
      }

      if (res.statusCode == 400) {
        final data = res.data;
        final detail =
            data is Map<String, dynamic> ? data['detail'] as String? : null;
        return AuthResult.failure(detail ?? 'Registration failed');
      }
      return AuthResult.failure('Registration failed. Please try again.');
    } on DioException catch (e) {
      return AuthResult.failure(_dioErrorMessage(e));
    } catch (e) {
      return AuthResult.failure(
          'An unexpected error occurred. Please try again.');
    }
  }

  Future<AuthResult> login(String email, String password) async {
    try {
      final res = await _client.post(
        '/api/v1/auth/login',
        data: {'email': email.trim(), 'password': password},
      );

      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        if (token != null) {
          await _client.setToken(token);
          return AuthResult.success();
        }
      }

      if (res.statusCode == 401) {
        return AuthResult.failure('Incorrect email or password');
      }
      return AuthResult.failure('Login failed. Please try again.');
    } on DioException catch (e) {
      return AuthResult.failure(_dioErrorMessage(e));
    } catch (e) {
      return AuthResult.failure(
          'An unexpected error occurred. Please try again.');
    }
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
    return res.data as Map<String, dynamic>?;
  }

  String _dioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Unable to connect to server. Please check your internet connection.';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Server took too long to respond. Please try again.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
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
