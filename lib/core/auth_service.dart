import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'package:garbanzo_ai/core/api_client.dart';

/// Sentinel marking "argument not provided" in optional-null contexts.
const Object _unset = Object();

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _client = ApiClient.instance;

  UserInfo? _cachedUser;

  /// The most recently fetched [UserInfo], or null if none has been fetched yet.
  /// Cleared on [logout]. Refreshed by calling [getCurrentUser].
  UserInfo? get cachedUser => _cachedUser;

  /// Update the authenticated user's profile. Any omitted parameter is
  /// left unchanged. Pass an explicit `null` to [defaultModel] to clear it.
  Future<AuthResult> updateProfile({
    String? fullName,
    String? email,
    Object? defaultModel = _unset,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (fullName != null) body['full_name'] = fullName.trim();
      if (email != null) body['email'] = email.trim();
      if (!identical(defaultModel, _unset)) {
        body['default_model'] = defaultModel;
      }
      if (body.isEmpty) return AuthResult.success();

      final res = await _client.patch('/api/v1/auth/me', data: body);
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        _cachedUser = UserInfo.fromJson(res.data as Map<String, dynamic>);
        return AuthResult.success();
      }
      final data = res.data;
      final detail = data is Map<String, dynamic>
          ? data['detail'] as String?
          : null;
      return AuthResult.failure(detail ?? 'Failed to update profile');
    } on DioException catch (e) {
      return AuthResult.failure(_dioErrorMessage(e));
    } catch (_) {
      return AuthResult.failure('Failed to update profile');
    }
  }

  /// Change the authenticated user's password.
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final res = await _client.post(
        '/api/v1/auth/me/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      if (res.statusCode == 204) return AuthResult.success();
      if (res.statusCode == 401) {
        return AuthResult.failure('Current password is incorrect');
      }
      final data = res.data;
      final detail = data is Map<String, dynamic>
          ? data['detail'] as String?
          : null;
      return AuthResult.failure(detail ?? 'Failed to change password');
    } on DioException catch (e) {
      return AuthResult.failure(_dioErrorMessage(e));
    } catch (_) {
      return AuthResult.failure('Failed to change password');
    }
  }

  /// Upload a profile picture. [imageBytes] should be raw image file bytes.
  /// Returns the updated [UserInfo] on success, or null on failure.
  Future<UserInfo?> uploadAvatar(Uint8List imageBytes, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(imageBytes, filename: filename),
      });
      final res = await _client.postMultipart(
        '/api/v1/auth/me/avatar',
        data: formData,
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        _cachedUser = UserInfo.fromJson(res.data as Map<String, dynamic>);
        return _cachedUser;
      }
      return null;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Remove the current profile picture.
  Future<UserInfo?> deleteAvatar() async {
    try {
      final res = await _client.delete('/api/v1/auth/me/avatar');
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        _cachedUser = UserInfo.fromJson(res.data as Map<String, dynamic>);
        return _cachedUser;
      }
      return null;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Report the device's IANA timezone and locale to the backend when they
  /// differ from what the server has stored — they feed the dynamic
  /// `<context>` block the backend injects into every chat prompt so
  /// "today" / "this weekend" resolve in the user's local time.
  ///
  /// Fire-and-forget from session start and login; failures are swallowed —
  /// a stale timezone only means the assistant's sense of local time lags
  /// until the next app start.
  Future<void> syncDeviceContext() async {
    try {
      final user = _cachedUser ?? await getCurrentUser();
      if (user == null) return;
      final tz = (await FlutterTimezone.getLocalTimezone()).identifier;
      final locale = PlatformDispatcher.instance.locale.toLanguageTag();
      final body = deviceContextPatch(user: user, timezone: tz, locale: locale);
      if (body.isEmpty) return;
      final res = await _client.patch('/api/v1/auth/me', data: body);
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        _cachedUser = UserInfo.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {
      // Best-effort: never let a timezone report break login/startup.
    }
  }

  /// The PATCH body [syncDeviceContext] sends: only the fields that are
  /// non-empty on the device and differ from what the server already has,
  /// so the common case (nothing moved) is no request at all.
  @visibleForTesting
  static Map<String, dynamic> deviceContextPatch({
    required UserInfo user,
    required String timezone,
    required String locale,
  }) {
    return <String, dynamic>{
      if (timezone.isNotEmpty && timezone != user.timezone)
        'timezone': timezone,
      if (locale.isNotEmpty && locale != user.locale) 'locale': locale,
    };
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
        final refreshToken = data['refresh_token'] as String?;
        if (token != null) {
          await _client.setTokens(
            accessToken: token,
            refreshToken: refreshToken,
          );
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
        'An unexpected error occurred. Please try again.',
      );
    }
  }

  Future<void> logout() async {
    _cachedUser = null;
    await _client.setTokens(accessToken: null, refreshToken: null);
  }

  Future<bool> isLoggedIn() async {
    final token = await _client.getToken();
    if (token == null) return false;
    try {
      final res = await _client.get('/api/v1/auth/me');
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        _cachedUser = UserInfo.fromJson(res.data as Map<String, dynamic>);
        return true;
      }
      return false;
    } on DioException {
      // Backend unreachable — treat as not-logged-in so the UI falls through
      // to the login screen instead of hanging on the splash spinner.
      return false;
    }
  }

  /// Fetch the current authenticated user from the backend and cache the
  /// result in [cachedUser]. Returns null on error.
  Future<UserInfo?> getCurrentUser() async {
    try {
      final res = await _client.get('/api/v1/auth/me');
      if (res.statusCode != 200) return null;
      final data = res.data;
      if (data is! Map<String, dynamic>) return null;
      final user = UserInfo.fromJson(data);
      _cachedUser = user;
      return user;
    } on DioException {
      return null;
    }
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
  factory AuthResult.failure(String message) =>
      AuthResult._(success: false, error: message);
}

/// Information about the currently-authenticated user returned by `/auth/me`.
class UserInfo {
  final String email;
  final String? fullName;
  final DateTime? createdAt;
  final bool isAdmin;
  final bool isDisabled;
  final String? defaultModel;
  final String? profilePictureB64;
  final String? timezone;
  final String? locale;

  const UserInfo({
    required this.email,
    this.fullName,
    this.createdAt,
    this.isAdmin = false,
    this.isDisabled = false,
    this.defaultModel,
    this.profilePictureB64,
    this.timezone,
    this.locale,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parsedCreatedAt;
    final createdRaw = json['created_at'];
    if (createdRaw is String && createdRaw.isNotEmpty) {
      parsedCreatedAt = DateTime.tryParse(createdRaw);
    }
    return UserInfo(
      email: (json['email'] as String?) ?? '',
      fullName: json['full_name'] as String?,
      createdAt: parsedCreatedAt,
      isAdmin: json['is_admin'] as bool? ?? false,
      isDisabled: json['is_disabled'] as bool? ?? false,
      defaultModel: json['default_model'] as String?,
      profilePictureB64: json['profile_picture_b64'] as String?,
      timezone: json['timezone'] as String?,
      locale: json['locale'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'email': email,
    'full_name': fullName,
    'created_at': createdAt?.toIso8601String(),
    'is_admin': isAdmin,
    'is_disabled': isDisabled,
    'default_model': defaultModel,
    'profile_picture_b64': profilePictureB64,
    'timezone': timezone,
    'locale': locale,
  };
}
