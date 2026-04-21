import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';

ChatMessage _callMsg() => ChatMessage(
      id: 'tc-1',
      role: 'tool_call',
      content: 'read_file',
      createdAt: DateTime(2024, 1, 1),
      metadata: const {
        'tool_calls': [
          {
            'id': 'call-1',
            'name': 'read_file',
            'arguments': {'path': '/tmp/foo.txt'},
          },
        ],
      },
    );

ChatMessage _resultMsg() => ChatMessage(
      id: 'tr-1',
      role: 'tool_result',
      content: 'read_file',
      createdAt: DateTime(2024, 1, 1),
      metadata: const {
        'tool_result': {
          'tool_call_id': 'call-1',
          'tool_name': 'read_file',
          'result': 'file contents here',
        },
      },
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ToolBubbleWidget', () {
    testWidgets('renders tool_call title', (tester) async {
      await tester.pumpWidget(_wrap(ToolBubbleWidget(message: _callMsg())));
      expect(find.text('Called read_file'), findsOneWidget);
    });

    testWidgets('shows spinner when streaming a tool_call', (tester) async {
      await tester.pumpWidget(_wrap(
        ToolBubbleWidget(message: _callMsg(), isStreaming: true),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('no spinner when tool_call is not streaming',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ToolBubbleWidget(message: _callMsg(), isStreaming: false),
      ));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tool_call expands to show input JSON', (tester) async {
      await tester.pumpWidget(_wrap(ToolBubbleWidget(message: _callMsg())));
      // Tap the ExpansionTile header
      await tester.tap(find.text('Called read_file'));
      await tester.pumpAndSettle();
      expect(find.text('Input'), findsOneWidget);
      expect(
        find.textContaining('/tmp/foo.txt', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('renders tool_result title and output', (tester) async {
      await tester.pumpWidget(_wrap(ToolBubbleWidget(message: _resultMsg())));
      expect(find.text('Result: read_file'), findsOneWidget);
      await tester.tap(find.text('Result: read_file'));
      await tester.pumpAndSettle();
      expect(find.text('Output'), findsOneWidget);
      expect(
        find.textContaining('file contents here', findRichText: true),
        findsWidgets,
      );
    });
  });
}
