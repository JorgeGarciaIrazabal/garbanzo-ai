import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

ChatMessage _msg(String id, {String role = 'assistant'}) => ChatMessage(
  id: id,
  role: role,
  content: 'content $id',
  createdAt: DateTime.utc(2026),
);

/// Fake ChatService with scriptable get/getOlder responses for B-03's
/// windowed-load + scroll-to-top paging.
class _FakeChatService extends ChatService {
  _FakeChatService() : super.forTesting();

  Conversation? conversationToReturn;
  int? lastRequestedLimit;
  final List<String> getConversationLimits = [];

  (List<ChatMessage>, bool)? olderPageToReturn;
  String? lastBeforeId;

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 50,
  }) async {
    return const ConversationList(items: [], total: 0, page: 1, pageSize: 50);
  }

  @override
  Future<Conversation> getConversation(
    String conversationId, {
    int? messageLimit,
  }) async {
    getConversationLimits.add('$messageLimit');
    return conversationToReturn!;
  }

  @override
  Future<(List<ChatMessage>, bool)> getOlderMessages(
    String conversationId,
    String beforeMessageId, {
    int limit = 50,
  }) async {
    lastBeforeId = beforeMessageId;
    return olderPageToReturn ?? (const <ChatMessage>[], false);
  }

  @override
  Stream<ChatResponseChunk> streamChatResponse(
    String conversationId,
    String message, {
    List<ChatAttachment> attachments = const [],
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
    bool hasClientFolder = false,
    String? clientFolderLabel,
    String? talkModeInstruction,
  }) {
    return const Stream.empty();
  }
}

void main() {
  group('ChatProvider windowed loading (B-03)', () {
    test('loadConversation requests the initial window, not everything', () async {
      final service = _FakeChatService()
        ..conversationToReturn = Conversation(
          id: 'c1',
          title: 'Test',
          model: 'llama3.2',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          messages: [_msg('m1'), _msg('m2')],
          hasMoreMessages: true,
        );
      final provider = ChatProvider(
        selectedModelId: 'llama3.2',
        chatService: service,
      );

      await provider.loadConversation('c1');

      expect(service.getConversationLimits, ['60']);
      expect(provider.messages.map((m) => m.id), ['m1', 'm2']);
      expect(provider.hasMoreMessages, isTrue);
      provider.dispose();
    });

    test('loadOlderMessages prepends the page and updates hasMoreMessages',
        () async {
      final service = _FakeChatService()
        ..conversationToReturn = Conversation(
          id: 'c1',
          title: 'Test',
          model: 'llama3.2',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          messages: [_msg('m5'), _msg('m6')],
          hasMoreMessages: true,
        )
        ..olderPageToReturn = ([_msg('m3'), _msg('m4')], false);
      final provider = ChatProvider(
        selectedModelId: 'llama3.2',
        chatService: service,
      );
      await provider.loadConversation('c1');

      await provider.loadOlderMessages();

      expect(service.lastBeforeId, 'm5'); // oldest currently loaded
      expect(provider.messages.map((m) => m.id), ['m3', 'm4', 'm5', 'm6']);
      expect(provider.hasMoreMessages, isFalse);
      provider.dispose();
    });

    test('post-turn reload requests at least what is already displayed',
        () async {
      final service = _FakeChatService()
        ..conversationToReturn = Conversation(
          id: 'c1',
          title: 'Test',
          model: 'llama3.2',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          messages: [for (var i = 0; i < 100; i++) _msg('m$i')],
        );
      final provider = ChatProvider(
        selectedModelId: 'llama3.2',
        chatService: service,
      );
      await provider.loadConversation('c1');

      // Empty stream → onDone → _reloadCurrentConversation. By then the
      // user message is in the list (100 + 1), so the reload must ask for
      // at least that many, not shrink back to the initial window.
      await provider.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.getConversationLimits, ['60', '101']);
      provider.dispose();
    });

    test('post-turn reload falls back to full history past the backend cap',
        () async {
      final service = _FakeChatService()
        ..conversationToReturn = Conversation(
          id: 'c1',
          title: 'Test',
          model: 'llama3.2',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          messages: [for (var i = 0; i < 501; i++) _msg('m$i')],
        );
      final provider = ChatProvider(
        selectedModelId: 'llama3.2',
        chatService: service,
      );
      await provider.loadConversation('c1');

      // 501 loaded + the new user message exceeds the backend's
      // message_limit cap (le=500) — a capped request would 422, so the
      // reload must drop the limit and fetch the full history instead.
      await provider.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.getConversationLimits, ['60', 'null']);
      provider.dispose();
    });

    test('loadOlderMessages is a no-op when there is nothing more', () async {
      final service = _FakeChatService()
        ..conversationToReturn = Conversation(
          id: 'c1',
          title: 'Test',
          model: 'llama3.2',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          messages: [_msg('m1')],
        );
      final provider = ChatProvider(
        selectedModelId: 'llama3.2',
        chatService: service,
      );
      await provider.loadConversation('c1');

      await provider.loadOlderMessages();

      expect(service.lastBeforeId, isNull);
      expect(provider.messages.map((m) => m.id), ['m1']);
      provider.dispose();
    });
  });
}
