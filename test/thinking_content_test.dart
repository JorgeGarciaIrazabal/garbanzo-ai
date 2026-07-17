import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/thinking_content.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Widget _wrap({
  bool isLive = false,
  String text = 'reasoning…',
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Scaffold(
          body: ThinkingContent(
            thinkingContent: text,
            colorScheme: theme.colorScheme,
            textTheme: theme.textTheme,
            isLive: isLive,
          ),
        );
      },
    ),
  );
}

void main() {
  group('ThinkingContent collapse behaviour', () {
    testWidgets('collapsed by default when isLive=false', (tester) async {
      await tester.pumpWidget(_wrap(isLive: false, text: 'past reasoning'));
      expect(find.text('Show thinking'), findsOneWidget);
      expect(find.text('Hide thinking'), findsNothing);
    });

    testWidgets('collapsed by default even while streaming (isLive=true)',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: true, text: 'live reasoning'));
      // Use pump (not pumpAndSettle) because the live-state SkeletonPulse
      // runs a repeating animation that never settles.
      await tester.pump();
      expect(find.text('Show thinking'), findsOneWidget);
      expect(find.text('Hide thinking'), findsNothing);
    });

    testWidgets('expands to reveal reasoning only when the user taps',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: false, text: 'the reasoning'));
      expect(find.text('Show thinking'), findsOneWidget);

      await tester.tap(find.text('Show thinking'));
      await tester.pumpAndSettle();
      expect(find.text('Hide thinking'), findsOneWidget);
      expect(find.text('the reasoning'), findsOneWidget);
    });

    testWidgets('stays collapsed across live→idle transitions on its own',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: true, text: 'r'));
      await tester.pump();
      expect(find.text('Show thinking'), findsOneWidget);

      await tester.pumpWidget(_wrap(isLive: false, text: 'r'));
      await tester.pumpAndSettle();
      expect(find.text('Show thinking'), findsOneWidget);
    });

    testWidgets('preserves the user choice once they expand the section',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: true, text: 'r'));
      await tester.tap(find.text('Show thinking'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hide thinking'), findsOneWidget);

      // Stream finishes — the user's expanded choice must be preserved.
      await tester.pumpWidget(_wrap(isLive: false, text: 'r'));
      await tester.pumpAndSettle();
      expect(find.text('Hide thinking'), findsOneWidget);
    });
  });
}
