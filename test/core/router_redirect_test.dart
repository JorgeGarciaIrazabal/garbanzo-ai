import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/core/router.dart';

void main() {
  group('computeRedirect', () {
    test('unauthenticated users are sent to /login from anywhere', () {
      for (final location in ['/', '/chat', '/chat/abc', '/rooms/1', '/kb']) {
        expect(
          computeRedirect(loggedIn: false, matchedLocation: location),
          '/login',
          reason: 'from $location',
        );
      }
    });

    test('unauthenticated users may stay on /login', () {
      expect(
        computeRedirect(loggedIn: false, matchedLocation: '/login'),
        isNull,
      );
    });

    test('logged-in users are bounced off /login and / to /chat', () {
      expect(
        computeRedirect(loggedIn: true, matchedLocation: '/login'),
        '/chat',
      );
      expect(computeRedirect(loggedIn: true, matchedLocation: '/'), '/chat');
    });

    test('logged-in users stay wherever they deep-link to', () {
      for (final location in [
        '/chat',
        '/chat/abc-123',
        '/rooms',
        '/rooms/42',
        '/settings',
        '/memory',
        '/kb',
        '/usage',
        '/notifications',
        '/skills',
        '/scheduled-actions',
        '/admin',
      ]) {
        expect(
          computeRedirect(loggedIn: true, matchedLocation: location),
          isNull,
          reason: 'at $location',
        );
      }
    });
  });
}
