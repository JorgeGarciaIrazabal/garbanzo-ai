import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/core/router.dart' show rootNavigatorKey;
import 'package:garbanzo_ai/features/settings/providers/update_provider.dart';
import 'package:garbanzo_ai/features/settings/services/update_installer.dart';
import 'package:garbanzo_ai/features/settings/services/update_service.dart';
import 'package:garbanzo_ai/features/settings/widgets/update_banner.dart';
import 'package:garbanzo_ai/features/settings/widgets/update_dialog.dart';

UpdateService _serviceWithUpdate() => UpdateService(
  apiGet: (_) async => Response(
    requestOptions: RequestOptions(path: ''),
    statusCode: 200,
    data: {
      'version': '9.9.9',
      'tag_name': 'v9.9.9',
      'body': 'notes',
      'html_url': 'https://example.com/release',
      'assets': [
        {
          'name': 'garbanzo-ai-linux-9.9.9.tar.gz',
          'download_url': 'https://example.com/a.tar.gz',
          'size': 1,
        },
      ],
    },
  ),
  currentVersion: () async => '1.0.0',
);

/// Mirrors main.dart: the banner wraps the router's Navigator via the
/// MaterialApp builder, so it lives ABOVE the Navigator in the tree.
Widget _app(UpdateProvider provider) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
    ],
  );
  return ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => UpdateBanner(child: child!),
    ),
  );
}

/// Runs the provider's startup check pretending to be on Linux desktop.
/// The override is reset before any widget pumping — testWidgets asserts
/// foundation debug variables are untouched at the end of the test body.
Future<void> _checkAsDesktop(UpdateProvider provider) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await provider.silentCheck();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('banner shows when an update is available and Later snoozes it', (
    tester,
  ) async {
    final provider = UpdateProvider(
      service: _serviceWithUpdate(),
      installer: UpdateInstaller(),
    );
    await _checkAsDesktop(provider);

    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    expect(find.text('Garbanzo AI v9.9.9 is available'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('update_banner_later')));
    await tester.pumpAndSettle();
    expect(find.text('Garbanzo AI v9.9.9 is available'), findsNothing);
  });

  testWidgets(
    'Update opens the changelog dialog even though the banner sits above '
    'the Navigator',
    (tester) async {
      final provider = UpdateProvider(
        service: _serviceWithUpdate(),
        installer: UpdateInstaller(),
      );
      await _checkAsDesktop(provider);

      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('update_banner_update')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(UpdateDialog), findsOneWidget);
      expect(find.text('Update to v9.9.9'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('update_install_button')),
        findsOneWidget,
      );
      // Banner is dismissed for the session once the dialog is opened.
      expect(find.text('Garbanzo AI v9.9.9 is available'), findsNothing);
    },
  );

  testWidgets('no banner when up to date', (tester) async {
    final provider = UpdateProvider(
      service: UpdateService(
        apiGet: (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'version': '1.0.0',
            'tag_name': 'v1.0.0',
            'html_url': '',
            'assets': [],
          },
        ),
        currentVersion: () async => '1.0.0',
      ),
      installer: UpdateInstaller(),
    );
    await _checkAsDesktop(provider);

    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    expect(find.textContaining('is available'), findsNothing);
  });
}
