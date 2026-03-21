import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/auth_service.dart';

void main() {
  group('AuthResult', () {
    test('success factory creates successful result', () {
      final result = AuthResult.success();
      expect(result.success, true);
      expect(result.error, isNull);
    });

    test('failure factory creates failed result with message', () {
      final result = AuthResult.failure('Invalid credentials');
      expect(result.success, false);
      expect(result.error, 'Invalid credentials');
    });

    test('failure preserves error message', () {
      const message = 'Unable to connect to server. Please check your internet connection.';
      final result = AuthResult.failure(message);
      expect(result.error, message);
    });
  });
}
