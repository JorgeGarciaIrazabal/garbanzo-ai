import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_activity_group.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

ChatMessage _call(String name, {String id = 'c'}) => ChatMessage(
      id: id,
      role: 'tool_call',
      content: name,
      createdAt: DateTime(2024, 1, 1),
      metadata: {
        'tool_calls': [
          {'id': id, 'name': name, 'arguments': const {}},
        ],
      },
    );

ChatMessage _result(String name, {String id = 'r'}) => ChatMessage(
      id: id,
      role: 'tool_result',
      content: name,
      createdAt: DateTime(2024, 1, 1),
      metadata: {
        'tool_result': {
          'tool_call_id': id,
          'tool_name': name,
          'result': 'ok',
        },
      },
    );

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(body: child));

void main() {
  group('ToolActivityGroup', () {
    testWidgets(
        'singular header reads "Used <name>" for one completed call',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('get_time'), _result('get_time')],
      )));
      expect(find.text('Used get_time'), findsOneWidget);
    });

    testWidgets('plural header for multiple completed calls', (tester) async {
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [
          _call('a', id: '1'),
          _result('a', id: '1'),
          _call('b', id: '2'),
          _result('b', id: '2'),
        ],
      )));
      expect(find.text('Used 2 tools'), findsOneWidget);
    });

    testWidgets(
        'header shows "Calling X…" with spinner while a call is pending',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('search')],
        isStreaming: true,
      )));
      expect(find.text('Calling search…'), findsOneWidget);
      // ≥1 spinner — there's also one in the (offstage) body's bubble.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets(
        'no spinner once streaming has finished and result is in',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('search'), _result('search')],
        isStreaming: false,
      )));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Used search'), findsOneWidget);
    });

    testWidgets(
        'shows "Working on response…" while waiting for the model after '
        'a tool result has come back', (tester) async {
      // The trailing message is a tool_result and the stream is still in
      // flight — meaning we just got the tool's output and are waiting for
      // the next assistant reply. This used to render as "Used X" with no
      // spinner, which made the UI feel frozen during multi-iteration runs.
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('search'), _result('search')],
        isStreaming: true,
      )));
      expect(find.text('Working on response…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('children are hidden until the header is tapped',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('search'), _result('search')],
      )));
      // The expanded body holds ToolBubbleWidgets; the AnimatedCrossFade
      // keeps the second child's widgets in the tree but with size zero, so
      // we assert by text content of the header rather than absence.
      expect(find.text('Used search'), findsOneWidget);

      // Tap to expand and verify the bubble renders.
      await tester.tap(find.text('Used search'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolBubbleWidget), findsNWidgets(2));
    });
  });
}
