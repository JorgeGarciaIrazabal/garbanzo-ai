import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';

ChatMessage _callMsg({String name = 'read_file'}) => ChatMessage(
      id: 'tc-1',
      role: 'tool_call',
      content: name,
      createdAt: DateTime(2024, 1, 1),
      metadata: {
        'tool_calls': [
          {
            'id': 'call-1',
            'name': name,
            'arguments': const {'path': '/tmp/foo.txt'},
          },
        ],
      },
    );

ChatMessage _resultMsg({Object result = 'file contents here'}) => ChatMessage(
      id: 'tr-1',
      role: 'tool_result',
      content: 'read_file',
      createdAt: DateTime(2024, 1, 1),
      metadata: {
        'tool_result': {
          'tool_call_id': 'call-1',
          'tool_name': 'read_file',
          'result': result,
        },
      },
    );

ChatMessage _errorResultMsg() => ChatMessage(
      id: 'tr-err',
      role: 'tool_result',
      content: 'read_file',
      createdAt: DateTime(2024, 1, 1),
      metadata: const {
        'tool_result': {
          'tool_call_id': 'call-1',
          'tool_name': 'read_file',
          'result': {'ok': false, 'error': 'boom'},
        },
      },
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ToolBubbleWidget — compact layout', () {
    testWidgets('tool_call shows compact label, name, and inline args',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolBubbleWidget(message: _callMsg())));

      // The compact header carries: a "call" badge, the tool name, and an
      // inline preview of the arguments.
      expect(find.text('call'), findsOneWidget);
      expect(find.text('read_file'), findsOneWidget);
      expect(find.textContaining('/tmp/foo.txt'), findsOneWidget);
    });

    testWidgets('tool_call collapsed view does NOT show full JSON block',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolBubbleWidget(message: _callMsg())));
      // The Input/Output section labels and pretty-printed JSON should be
      // hidden until the user expands. (They were always-visible before.)
      expect(find.text('Input'), findsNothing);
      expect(find.text('Output'), findsNothing);
    });

    testWidgets('tool_call expands to reveal pretty-printed args',
        (tester) async {
      await tester.pumpWidget(_wrap(ToolBubbleWidget(message: _callMsg())));
      await tester.tap(find.text('read_file'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('/tmp/foo.txt', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('shows spinner when streaming a tool_call', (tester) async {
      await tester.pumpWidget(_wrap(
        ToolBubbleWidget(message: _callMsg(), isStreaming: true),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('tool_result with success shows "result" badge',
        (tester) async {
      await tester
          .pumpWidget(_wrap(ToolBubbleWidget(message: _resultMsg())));
      expect(find.text('result'), findsOneWidget);
      expect(find.text('read_file'), findsOneWidget);
      expect(find.textContaining('file contents here'), findsOneWidget);
    });

    testWidgets('tool_result with ok=false shows "error" badge',
        (tester) async {
      await tester
          .pumpWidget(_wrap(ToolBubbleWidget(message: _errorResultMsg())));
      expect(find.text('error'), findsOneWidget);
      expect(find.text('result'), findsNothing);
    });
  });
}
