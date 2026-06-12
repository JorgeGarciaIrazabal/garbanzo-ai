import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/thinking_content.dart';

Widget _wrap({
  required bool isLive,
  bool hasContent = false,
  String text = 'reasoning…',
}) {
  return MaterialApp(
    home: Builder(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Scaffold(
          body: ThinkingContent(
            thinkingContent: text,
            colorScheme: theme.colorScheme,
            textTheme: theme.textTheme,
            isLive: isLive,
            hasContent: hasContent,
          ),
        );
      },
    ),
  );
}

void main() {
  group('ThinkingContent auto-expand behaviour', () {
    testWidgets('expanded while isLive=true so streaming reasoning is visible',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: true, text: 'live reasoning'));
      // The reasoning text is rendered inside the SecondChild of the
      // AnimatedCrossFade — when expanded, it's visible in the tree.
      expect(find.text('live reasoning'), findsOneWidget);
      expect(find.text('Hide thinking'), findsOneWidget);
    });

    testWidgets('collapsed by default when isLive=false', (tester) async {
      await tester.pumpWidget(_wrap(isLive: false, text: 'past reasoning'));
      expect(find.text('Show thinking'), findsOneWidget);
      expect(find.text('Hide thinking'), findsNothing);
    });

    testWidgets(
        'auto-collapses when the final answer arrives (hasContent flips true)',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: true, text: 'r'));
      expect(find.text('Hide thinking'), findsOneWidget);

      // Simulate the stream completing — answer content arrives and the
      // section should auto-collapse so the final answer takes the focus.
      await tester.pumpWidget(_wrap(isLive: false, hasContent: true, text: 'r'));
      await tester.pumpAndSettle();
      expect(find.text('Show thinking'), findsOneWidget);
    });

    testWidgets(
        'stays open when isLive flips false without an answer (tool call)',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: true, text: 'r'));
      expect(find.text('Hide thinking'), findsOneWidget);

      // A tool call elsewhere makes this message stop being the trailing
      // one — no answer yet, so the reasoning stays visible.
      await tester.pumpWidget(_wrap(isLive: false, text: 'r'));
      await tester.pumpAndSettle();
      expect(find.text('Hide thinking'), findsOneWidget);
    });

    testWidgets(
        'preserves user choice once they manually toggle the section',
        (tester) async {
      await tester.pumpWidget(_wrap(isLive: true, text: 'r'));
      // User collapses while still streaming.
      await tester.tap(find.text('Hide thinking'));
      await tester.pumpAndSettle();
      expect(find.text('Show thinking'), findsOneWidget);

      // Stream finishes — must not re-expand and must not flip back open.
      await tester.pumpWidget(_wrap(isLive: false, text: 'r'));
      await tester.pumpAndSettle();
      expect(find.text('Show thinking'), findsOneWidget);
    });
  });
}
