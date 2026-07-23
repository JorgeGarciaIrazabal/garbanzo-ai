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
}
