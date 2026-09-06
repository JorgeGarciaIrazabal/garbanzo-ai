import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

Conversation _conversation(
  String title, {
  List<ChatMessage> messages = const [],
}) => Conversation(
      id: 'conv-1',
      title: title,
      model: 'minimax-m3:cloud',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      messages: messages,
    );

class _SyncChatService extends ChatService {
  _SyncChatService() : super.forTesting();

  Conversation conversation = _conversation('Original');
  int getConversationCalls = 0;

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 50,
    bool silent = false,
    String kind = 'all',
  }) async => ConversationList(
    items: [conversation.copyWith(messages: null)],
    total: 1,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<Conversation> getConversation(
    String conversationId, {
    int? messageLimit,
    bool silent = false,
  }) async {
    getConversationCalls++;
    return conversation;
  }
}

void main() {
  test('foreground sync refreshes the sidebar and open conversation', () async {
    final service = _SyncChatService();
    final provider = ChatProvider(chatService: service);
    await provider.loadConversation('conv-1');

    service.conversation = _conversation(
      'Changed on another device',
      messages: [
        ChatMessage(
          id: 'remote-message',
          role: 'assistant',
          content: 'Arrived remotely',
          createdAt: DateTime.utc(2026),
        ),
      ],
    );

    await provider.syncFromServer();

    expect(provider.conversations.single.title, 'Changed on another device');
    expect(provider.currentConversation?.title, 'Changed on another device');
    expect(provider.messages.single.content, 'Arrived remotely');
    expect(service.getConversationCalls, 2);
    provider.dispose();
  });

  test('silent sync preserves a conversation pending deletion', () async {
    final service = _SyncChatService();
    final provider = ChatProvider(chatService: service);
    await provider.refreshConversations();

    await provider.deleteConversation('conv-1');
    await provider.syncFromServer();

    expect(provider.conversations, isEmpty);
    provider.undoDeleteConversation('conv-1');
    provider.dispose();
  });

  test('syncFromServer maintains empty messages after topic switch with new session epoch', () async {
    final service = _SyncChatService();
    final provider = ChatProvider(chatService: service);
    await provider.loadConversation('conv-1');

    provider.clearMessagesLocally();
    service.conversation = _conversation('New Topic', messages: []);

    await provider.syncFromServer();

    expect(provider.messages, isEmpty);
    provider.dispose();
  });

  test('clearMessagesLocally drops an in-flight pre-switch reload (bug 1ba9a9f8)', () async {
    final service = _SyncChatService();
    final provider = ChatProvider(chatService: service);
    await provider.loadConversation('conv-1');

    // A reload started before the topic switch (background sync tick) whose
    // response carries the OLD conversation (pre-switch topic + messages).
    final staleFuture = provider.reloadCurrentConversationForTest();
    provider.clearMessagesLocally();
    await staleFuture;

    // The stale reload must not resurrect the pre-switch topic/messages.
    expect(provider.messages, isEmpty);
    expect(provider.currentConversation?.contextSummary, isNull);
    provider.dispose();
  });

  test('clearMessagesLocally clears messages and resets contextSummary on current conversation', () async {
    final service = _SyncChatService();
    service.conversation = _conversation('Test', messages: [
      ChatMessage(id: 'm1', role: 'user', content: 'hello', createdAt: DateTime.utc(2026)),
    ]).copyWith(contextSummary: 'Old AI news summary');
    final provider = ChatProvider(chatService: service);
    await provider.loadConversation('conv-1');

    expect(provider.currentConversation?.contextSummary, 'Old AI news summary');
    expect(provider.messages, isNotEmpty);

    provider.clearMessagesLocally();

    expect(provider.messages, isEmpty);
    expect(provider.currentConversation?.contextSummary, isNull);
    provider.dispose();
  });
}
