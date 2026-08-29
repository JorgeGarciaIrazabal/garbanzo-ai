import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';
import 'package:garbanzo_ai/features/rooms/widgets/room_connection_banner.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Widget _app({
  required RoomConnectionState state,
  bool backOnline = false,
  VoidCallback? onRetry,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: RoomConnectionBanner(
      state: state,
      backOnline: backOnline,
      onRetry: onRetry ?? () {},
    ),
  ),
);

void main() {
  testWidgets('transient reconnect is calm and non-blocking', (tester) async {
    await tester.pumpWidget(_app(state: RoomConnectionState.reconnecting));

    expect(find.byKey(const ValueKey('room_reconnecting_banner')), findsOne);
    expect(find.text('Reconnecting…'), findsOne);
    expect(find.byType(CircularProgressIndicator), findsOne);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('successful recovery briefly says back online', (tester) async {
    await tester.pumpWidget(
      _app(state: RoomConnectionState.connected, backOnline: true),
    );

    expect(find.byKey(const ValueKey('room_back_online_banner')), findsOne);
    expect(find.text('Back online'), findsOne);
    expect(find.byIcon(Icons.check_circle_outline), findsOne);
  });

  testWidgets('terminal failure offers an inline retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        state: RoomConnectionState.failed,
        onRetry: () => retries++,
      ),
    );

    expect(find.text("Couldn't reconnect."), findsOne);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('connection statuses are localized in Spanish', (tester) async {
    await tester.pumpWidget(
      _app(
        state: RoomConnectionState.reconnecting,
        locale: const Locale('es'),
      ),
    );

    expect(find.text('Reconectando…'), findsOne);
  });
}
