import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_activity_group.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

ChatMessage _call(
  String name, {
  String id = 'c',
  Map<String, dynamic> arguments = const {},
}) => ChatMessage(
      id: id,
      role: 'tool_call',
      content: name,
      createdAt: DateTime(2024, 1, 1),
      metadata: {
        'tool_calls': [
          {'id': id, 'name': name, 'arguments': arguments},
        ],
      },
    );

ChatMessage _result(
  String name, {
  String id = 'r',
  Object result = 'ok',
  bool isError = false,
}) => ChatMessage(
      id: id,
      role: 'tool_result',
      content: name,
      createdAt: DateTime(2024, 1, 1),
      metadata: {
        'tool_result': {
          'tool_call_id': id,
          'tool_name': name,
          'result': result,
          'is_error': isError,
        },
      },
    );

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('ToolActivityGroup', () {
    testWidgets('completed generic activity uses a friendly step count',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('get_time'), _result('get_time')],
      )));
      expect(find.text('Completed 1 step'), findsOneWidget);
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
      expect(find.text('Completed 2 steps'), findsOneWidget);
    });

    testWidgets(
        'pending search uses a high-level researching label',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('web_search')],
        isStreaming: true,
      )));
      expect(find.text('Agent is working…'), findsOneWidget);
      expect(find.text('Researching information…'), findsOneWidget);
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
      expect(find.text('Completed 1 step'), findsOneWidget);
    });

    testWidgets(
        'continues to show agent activity while waiting for the model after '
        'a tool result has come back', (tester) async {
      // The trailing message is a tool_result and the stream is still in
      // flight — meaning we just got the tool's output and are waiting for
      // the next assistant reply. This used to render as "Used X" with no
      // spinner, which made the UI feel frozen during multi-iteration runs.
      await tester.pumpWidget(_wrap(ToolActivityGroup(
        messages: [_call('search'), _result('search')],
        isStreaming: true,
      )));
      expect(find.text('Agent is working…'), findsOneWidget);
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
      expect(find.text('Completed 1 step'), findsOneWidget);

      // Tap to expand and verify the bubble renders.
      await tester.tap(find.text('Completed 1 step'));
      await tester.pumpAndSettle();
      expect(find.text('Exploring app files…'), findsWidgets);

      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolBubbleWidget), findsNWidgets(2));
    });

    testWidgets('micro-app work opens as a live milestone timeline',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ToolActivityGroup(
            messages: [
              _call(
                'micro_app',
                id: 'outer',
                arguments: {
                  'app': 'family-dashboard',
                  'instruction': 'Build the first tab',
                  'edit': true,
                },
              ),
              _call(
                'read',
                id: 'read',
                arguments: {'filePath': 'apps/family-dashboard/lib/main.dart'},
              ),
              _result('read', id: 'read'),
              _call(
                'edit',
                id: 'edit',
                arguments: {'filePath': 'apps/family-dashboard/lib/home_tab.dart'},
              ),
            ],
            isStreaming: true,
          ),
        ),
      );

      expect(find.text('Building Family dashboard…'), findsOneWidget);
      expect(find.text('Reviewing main.dart…'), findsOneWidget);
      expect(find.text('Updating home_tab.dart…'), findsWidgets);
      expect(find.text('Technical details'), findsOneWidget);
    });

    testWidgets('completed micro-app activity reports success', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ToolActivityGroup(
            messages: [
              _call(
                'micro_app',
                id: 'outer',
                arguments: {'app': 'family-dashboard', 'edit': true},
              ),
              _call(
                'bash',
                id: 'check',
                arguments: {'command': 'npm run build'},
              ),
              _result('bash', id: 'check'),
              _result(
                'micro_app',
                id: 'outer',
                result: {'ok': true, 'app': 'family-dashboard'},
              ),
            ],
          ),
        ),
      );

      expect(find.text('Updated Family dashboard'), findsOneWidget);
    });
  });
}
