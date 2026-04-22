import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient token lifecycle', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('setToken(null) does not re-read stale token from prefs on next get',
        () async {
      // Pre-seed prefs with a stale token to simulate a previous session.
      SharedPreferences.setMockInitialValues({'auth_token': 'stale-token'});

      final client = ApiClient.instance;
      await client.loadToken();

      expect(await client.getToken(), 'stale-token');

      // Clear the in-memory token synchronously. The prefs.remove() is
      // still in flight, but getToken must not fall back to it.
      final future = client.setToken(null);
      expect(await client.getToken(), isNull,
          reason: 'After setToken(null), getToken must return null even if '
              'prefs.remove has not yet flushed');
      await future;
      expect(await client.getToken(), isNull);
    });

    test('setToken persists and survives a fresh getToken', () async {
      final client = ApiClient.instance;
      await client.loadToken();
      await client.setToken('fresh-token');
      expect(await client.getToken(), 'fresh-token');
    });

    test(
      'concurrent getTokens after clear all return null (no stale re-read)',
      () async {
        SharedPreferences.setMockInitialValues({'auth_token': 'stale'});
        final client = ApiClient.instance;
        await client.loadToken();

        // Fire setToken(null) and multiple getTokens in parallel. None of
        // them may observe the stale value once the clear has begun.
        final clear = client.setToken(null);
        final results = await Future.wait([
          client.getToken(),
          client.getToken(),
          client.getToken(),
        ]);
        await clear;
        for (final r in results) {
          expect(r, isNull);
        }
      },
    );
  });
}
