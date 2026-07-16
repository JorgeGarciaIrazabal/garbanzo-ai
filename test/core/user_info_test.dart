import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/auth_service.dart';

void main() {
  group('UserInfo.fromJson', () {
    test('parses a full payload', () {
      final user = UserInfo.fromJson({
        'email': 'jane@example.com',
        'full_name': 'Jane Doe',
        'created_at': '2026-01-02T03:04:05.000Z',
        'is_admin': true,
        'is_disabled': false,
        'default_model': 'qwen3.6',
        'timezone': 'America/New_York',
        'locale': 'en-US',
      });
      expect(user.email, 'jane@example.com');
      expect(user.fullName, 'Jane Doe');
      expect(user.createdAt, isNotNull);
      expect(user.createdAt!.toUtc().toIso8601String(),
          '2026-01-02T03:04:05.000Z');
      expect(user.isAdmin, isTrue);
      expect(user.isDisabled, isFalse);
      expect(user.defaultModel, 'qwen3.6');
      expect(user.timezone, 'America/New_York');
      expect(user.locale, 'en-US');
    });

    test('falls back to safe defaults for missing fields', () {
      final user = UserInfo.fromJson({});
      expect(user.email, '');
      expect(user.fullName, isNull);
      expect(user.createdAt, isNull);
      expect(user.isAdmin, isFalse);
      expect(user.isDisabled, isFalse);
      expect(user.defaultModel, isNull);
    });

    test('ignores malformed created_at', () {
      final user = UserInfo.fromJson({
        'email': 'a@b.c',
        'created_at': 'not-a-date',
      });
      expect(user.createdAt, isNull);
    });

    test('toJson round-trips key fields', () {
      const user = UserInfo(
        email: 'a@b.c',
        fullName: 'A B',
        isAdmin: true,
      );
      final json = user.toJson();
      expect(json['email'], 'a@b.c');
      expect(json['full_name'], 'A B');
      expect(json['is_admin'], isTrue);
      expect(json['is_disabled'], isFalse);
      expect(json['default_model'], isNull);
    });
  });

  group('AuthService.deviceContextPatch', () {
    const user = UserInfo(
      email: 'a@b.c',
      timezone: 'America/New_York',
      locale: 'en-US',
    );

    test('empty when device matches what the server has', () {
      final body = AuthService.deviceContextPatch(
        user: user,
        timezone: 'America/New_York',
        locale: 'en-US',
      );
      expect(body, isEmpty);
    });

    test('sends only the field that changed', () {
      final body = AuthService.deviceContextPatch(
        user: user,
        timezone: 'Europe/Madrid',
        locale: 'en-US',
      );
      expect(body, {'timezone': 'Europe/Madrid'});
    });

    test('sends both when the server has neither', () {
      final body = AuthService.deviceContextPatch(
        user: const UserInfo(email: 'a@b.c'),
        timezone: 'Europe/Madrid',
        locale: 'es-ES',
      );
      expect(body, {'timezone': 'Europe/Madrid', 'locale': 'es-ES'});
    });

    test('never sends empty device values over stored ones', () {
      final body = AuthService.deviceContextPatch(
        user: user,
        timezone: '',
        locale: '',
      );
      expect(body, isEmpty);
    });
  });
}
