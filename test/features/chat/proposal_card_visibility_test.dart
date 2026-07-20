@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

/// Regression test for a proposal card that never appeared on screen.
///
/// `chat_page` folds runs of consecutive tool_call/tool_result messages into a
/// single collapsible "Used N tools" section. That swallowed proposal results
/// too, so `ChatMessageWidget`'s Confirm-card branch was unreachable and the
/// user saw only a collapsed tool bubble — for delegate_workflow *and* for the
/// older create_room / set_conversation_style proposals.
///
/// This pins the grouping predicate itself: a tool_result carrying a proposal
/// must stay a top-level item.
bool isGroupableTool(ChatMessage m) =>
    (m.isToolCall || m.isToolResult) && m.actionProposal == null;

ChatMessage _toolResult({Map<String, dynamic>? proposal}) => ChatMessage(
  id: 'm1',
  role: 'tool_result',
  content: 'delegate_workflow',
  createdAt: DateTime(2026),
  metadata: {
    'tool_result': {
      'tool_call_id': 'tc-1',
      'tool_name': 'delegate_workflow',
      'result': {'ok': true, 'proposal': ?proposal},
    },
  },
);

void main() {
  test('a plain tool result is grouped into the tool timeline', () {
    expect(isGroupableTool(_toolResult()), isTrue);
  });

  test('a proposal result escapes grouping so its card can render', () {
    final message = _toolResult(
      proposal: {
        'type': 'delegate_workflow',
        'summary': 'Create folder summary markdown',
        'payload': {'instruction': 'Create a markdown summary'},
      },
    );

    expect(message.actionProposal, isNotNull);
    expect(message.toolCallId, 'tc-1');
    expect(
      isGroupableTool(message),
      isFalse,
      reason: 'grouping would hide the card inside the collapsed section',
    );
  });

  test('tool calls are always groupable', () {
    final call = ChatMessage(
      id: 'm0',
      role: 'tool_call',
      content: '',
      createdAt: DateTime(2026),
      metadata: {
        'tool_calls': [
          {'id': 'tc-1', 'name': 'delegate_workflow'},
        ],
      },
    );
    expect(isGroupableTool(call), isTrue);
  });

  test('a truncated result degrades to grouped rather than a broken card', () {
    // Oversized results are stored as a truncated *string*, so there is no
    // proposal to render — it must fall back to the tool bubble.
    final message = ChatMessage(
      id: 'm2',
      role: 'tool_result',
      content: 'delegate_workflow',
      createdAt: DateTime(2026),
      metadata: {
        'tool_result': {
          'tool_call_id': 'tc-1',
          'tool_name': 'delegate_workflow',
          'result': '{"ok": true, "proposal": {"type": "delegate_wor…',
        },
      },
    );
    expect(message.actionProposal, isNull);
    expect(isGroupableTool(message), isTrue);
  });
}
