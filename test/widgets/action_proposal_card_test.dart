import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/action_proposal_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage _proposalMessage({
  String type = 'create_room',
  String toolCallId = 'call-1',
  Map<String, dynamic>? payload,
}) {
  return ChatMessage(
    id: 'm1',
    role: 'tool_result',
    content: type,
    createdAt: DateTime(2026),
    metadata: {
      'tool_result': {
        'tool_call_id': toolCallId,
        'tool_name': type,
        'result': {
          'ok': true,
          'proposal': {
            'type': type,
            'summary': type == 'create_room'
                ? "Create room 'Research' with ana@example.com"
                : 'Set conversation style: thinking → high',
            'payload':
                payload ??
                {
                  'name': 'Research',
                  'member_emails': ['ana@example.com'],
                  'agents': [
                    {'name': 'Researcher', 'model': 'qwen3'},
                  ],
                },
          },
        },
      },
    },
  );
}

Widget _wrap(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
    ChangeNotifierProvider<ModelProvider>(create: (_) => ModelProvider()),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders summary, details, and Confirm/Cancel', (tester) async {
    await tester.pumpWidget(_wrap(ActionProposalCard(message: _proposalMessage())));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('action_proposal_card')), findsOneWidget);
    expect(
      find.text("Create room 'Research' with ana@example.com"),
      findsOneWidget,
    );
    expect(find.text('Agent: Researcher (qwen3, replies: mention)'), findsOneWidget);
    expect(find.byKey(const ValueKey('action_proposal_confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('action_proposal_cancel')), findsOneWidget);
  });

  testWidgets('cancel dismisses and the decision survives a rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(ActionProposalCard(message: _proposalMessage())));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('action_proposal_cancel')));
    await tester.pump();
    expect(find.text('Dismissed'), findsOneWidget);
    expect(find.byKey(const ValueKey('action_proposal_confirm')), findsNothing);

    // Fresh widget for the same proposal (as after an app reload): the
    // stored decision must keep the buttons gone — no re-confirm loophole.
    await tester.pumpWidget(_wrap(ActionProposalCard(message: _proposalMessage())));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dismissed'), findsOneWidget);
    expect(find.byKey(const ValueKey('action_proposal_confirm')), findsNothing);
  });

  testWidgets('a stored confirmed decision renders as done', (tester) async {
    SharedPreferences.setMockInitialValues({
      'action_proposal_decision_call-1': 'confirmed',
    });
    await tester.pumpWidget(_wrap(ActionProposalCard(message: _proposalMessage())));
    await tester.pump();
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const ValueKey('action_proposal_confirm')), findsNothing);
  });

  testWidgets(
    'confirming set_conversation_style without an active conversation fails '
    'gracefully and offers retry',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ActionProposalCard(
            message: _proposalMessage(
              type: 'set_conversation_style',
              payload: {
                'model': null,
                'thinking_level': 'high',
                'system_prompt': null,
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('action_proposal_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Failed'), findsOneWidget);
      // Failure keeps the buttons so the user can retry or dismiss.
      expect(
        find.byKey(const ValueKey('action_proposal_confirm')),
        findsOneWidget,
      );
    },
  );

  testWidgets('plain tool results expose no proposal', (tester) async {
    final message = ChatMessage(
      id: 'm2',
      role: 'tool_result',
      content: 'memories',
      createdAt: DateTime(2026),
      metadata: {
        'tool_result': {
          'tool_call_id': 'call-2',
          'tool_name': 'memories',
          'result': {'ok': true, 'count': 0},
        },
      },
    );
    expect(message.actionProposal, isNull);
  });
}
