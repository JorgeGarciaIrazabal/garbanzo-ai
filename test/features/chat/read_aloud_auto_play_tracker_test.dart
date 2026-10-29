import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/read_aloud_auto_play_tracker.dart';

void main() {
  test('visual auto-play uses summary and waits for its persisted ID', () {
    final tracker = ReadAloudAutoPlayTracker();
    ChatMessage visual(String id, {bool nested = false}) {
      final meta = <String, dynamic>{
        'tool_call_id': 'visual',
        'tool_name': 'render_ui',
        'result': {
          'ok': true,
          'presentation': {'summary': 'Three tasks are complete.'},
        },
      };
      return ChatMessage(
        id: id,
        role: 'tool_result',
        content: 'render_ui',
        createdAt: DateTime(2026),
        metadata: nested ? {'tool_result': meta} : meta,
      );
    }

    final live = visual('temp-tool-result-visual', nested: true);
    final saved = visual('saved-visual');
    final placeholder = ChatMessage(
      id: 'temp-placeholder',
      role: 'assistant',
      content: '',
      createdAt: DateTime(2026),
    );
    ChatMessage? observe(bool sending, List<ChatMessage> messages) =>
        tracker.observe(
          sending: sending,
          conversationId: 'thread',
          messages: messages,
          hasError: false,
        );
    expect(observe(true, []), isNull);
    expect(observe(false, [live, placeholder]), isNull);
    expect(observe(false, [saved])?.id, saved.id);
    expect(readableReplyContent(live), 'Three tasks are complete.');
    expect(readableReplyContent(saved), readableReplyContent(live));
    expect(observe(false, [saved]), isNull);
  });
  test('auto-play waits for the newly completed reply to have a stable ID', () {
    final tracker = ReadAloudAutoPlayTracker();
    ChatMessage reply(String id, String content) => ChatMessage(
      id: id,
      role: 'assistant',
      content: content,
      createdAt: DateTime(2026, 9, 23),
    );
    final history = reply('old', 'An older reply.');
    final empty = reply('temp-empty', '');
    final temporary = reply('temp-new', '<think>Private.</think>New answer.');
    final stable = reply('new', '<think>Private.</think>New answer.');

    ChatMessage? observe(bool sending, List<ChatMessage> messages) =>
        tracker.observe(
          sending: sending,
          conversationId: 'thread',
          messages: messages,
          hasError: false,
        );

    expect(observe(false, [history]), isNull); // Opening history never speaks.
    expect(observe(true, [history, empty]), isNull);
    expect(
      observe(false, [history]),
      isNull,
    ); // Empty turn leaves history alone.
    expect(observe(true, [history, temporary]), isNull);
    expect(observe(false, [history, temporary]), isNull);
    expect(observe(false, [history, stable])?.id, 'new');
    expect(observe(false, [history, stable]), isNull); // Exactly once.
    expect(visibleAssistantContent(stable.content), 'New answer.');

    final repeated = ReadAloudAutoPlayTracker();
    final oldSameText = reply('old-same', 'Repeated answer.');
    final temporarySameText = reply('temp-same', 'Repeated answer.');
    final newSameText = reply('new-same', 'Repeated answer.');
    List<ChatMessage> messages = [oldSameText];
    ChatMessage? observeRepeated(bool sending) => repeated.observe(
      sending: sending,
      conversationId: 'thread',
      messages: messages,
      hasError: false,
    );
    expect(observeRepeated(false), isNull);
    messages = [oldSameText, temporarySameText];
    expect(observeRepeated(true), isNull);
    expect(observeRepeated(false), isNull);
    messages = [oldSameText]; // A stale reload still shows the previous reply.
    expect(observeRepeated(false), isNull);
    messages = [oldSameText, newSameText];
    expect(observeRepeated(false)?.id, 'new-same');
  });
}
