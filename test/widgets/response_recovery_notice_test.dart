import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/response_recovery_notice.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Widget _app(ChatResponseRecoveryState state) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ResponseRecoveryNotice(state: state)),
  );
}

void main() {
  testWidgets('uses a neutral offline status instead of an error banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(ChatResponseRecoveryState.waitingForConnection),
    );

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.textContaining('Your response is still running'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('shows syncing state after the server is reachable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(ChatResponseRecoveryState.syncing));

    expect(find.byIcon(Icons.cloud_sync_outlined), findsOneWidget);
    expect(find.text('Back online. Syncing your response…'), findsOneWidget);
  });
}
