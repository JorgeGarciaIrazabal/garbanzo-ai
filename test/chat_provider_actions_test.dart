import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

/// Fake ChatService for exercising ChatProvider's message actions
/// (send / regenerate / edit / branch / pin). Streams are driven by the
/// test through [controller]; every action call is recorded.
class _FakeChatService extends ChatService {
  _FakeChatService() : super.forTesting();

  final StreamController<ChatResponseChunk> controller =
      StreamController<ChatResponseChunk>();

  /// Server-side view of each conversation, returned by [getConversation]
  /// and [listConversations]. Tests mutate entries to simulate server state.
  final Map<String, Conversation> conversationsById = {
    'conv-1': _conversation('conv-1'),
  };

  static Conversation _conversation(
    String id, {
    List<ChatMessage> messages = const [],
    bool isPinned = false,
  }) {
    return Conversation(
      id: id,
      title: 'Test',
      model: 'llama3.2',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      isPinned: isPinned,
      messages: messages,
    );
  }

  void seedMessages(String conversationId, List<ChatMessage> messages) {
    conversationsById[conversationId] = conversationsById[conversationId]!
        .copyWith(messages: messages);
  }

  final List<({String conversationId, String messageId})> regenerateCalls = [];
  final List<({String conversationId, String messageId, String content})>
  editCalls = [];
  final List<({String conversationId, String messageId})> branchCalls = [];
  final List<({String conversationId, bool? isPinned})> updateCalls = [];
  int streamChatCalls = 0;

  /// When set, the corresponding call throws instead of succeeding.
  Exception? streamChatError;
  Exception? branchError;

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 50,
  }) async {
    final items = conversationsById.values.toList();
    return ConversationList(
      items: items,
      total: items.length,
      page: 1,
      pageSize: 50,
    );
  }

  @override
  Future<Conversation> getConversation(
    String conversationId, {
    int? messageLimit,
  }) async {
    return conversationsById[conversationId]!;
  }

  @override
  Future<Conversation> updateConversation(
    String conversationId, {
    String? title,
    String? model,
    bool? useMemory,
    bool? useKnowledgeBase,
    String? systemPrompt,
    bool clearSystemPrompt = false,
    List<String>? enabledTools,
    bool clearEnabledTools = false,
    bool? isPinned,
    ThinkingLevel? thinkingLevel,
    bool setThinkingLevel = false,
  }) async {
    updateCalls.add((conversationId: conversationId, isPinned: isPinned));
    final updated = conversationsById[conversationId]!.copyWith(
      title: title ?? conversationsById[conversationId]!.title,
      isPinned: isPinned ?? conversationsById[conversationId]!.isPinned,
    );
    conversationsById[conversationId] = updated;
    return updated;
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
    streamChatCalls++;
    if (streamChatError != null) throw streamChatError!;
    return controller.stream;
  }

  @override
  Stream<ChatResponseChunk> regenerateMessage(
    String conversationId,
    String messageId, {
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
  }) {
    regenerateCalls.add((
      conversationId: conversationId,
      messageId: messageId,
    ));
    return controller.stream;
  }

  @override
  Stream<ChatResponseChunk> editMessage(
    String conversationId,
    String messageId,
    String newContent, {
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
  }) {
    editCalls.add((
      conversationId: conversationId,
      messageId: messageId,
      content: newContent,
    ));
    return controller.stream;
  }

  @override
  Future<Conversation> branchConversation(
    String conversationId,
    String messageId,
  ) async {
    branchCalls.add((conversationId: conversationId, messageId: messageId));
    if (branchError != null) throw branchError!;
    final branched = _conversation('conv-branched');
    conversationsById['conv-branched'] = branched;
    return branched;
  }

  @override
  Future<void> stopStreaming(String conversationId) async {}

  @override
  Future<void> deleteConversation(String conversationId) async {}
}

ChatMessage _msg(String id, String role, String content) => ChatMessage(
  id: id,
  role: role,
  content: content,
  createdAt: DateTime.utc(2026),
);

Future<ChatProvider> _openConversation(_FakeChatService service) async {
  final provider = ChatProvider(
    selectedModelId: 'llama3.2',
    chatService: service,
  );
  await provider.loadConversation('conv-1');
  return provider;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('regenerateLastAssistant', () {
    test('trims the old reply, re-streams, and reconciles with the server',
        () async {
      final service = _FakeChatService();
      service.seedMessages('conv-1', [
        _msg('u1', 'user', 'question'),
        _msg('a1', 'assistant', 'old answer'),
      ]);
      final provider = await _openConversation(service);

      await provider.regenerateLastAssistant();

      expect(
        service.regenerateCalls,
        [(conversationId: 'conv-1', messageId: 'a1')],
      );
      expect(provider.isSending, isTrue);
      // Old assistant reply trimmed optimistically; a streaming placeholder
      // sits at the end.
      expect(provider.messages.first.content, 'question');
      expect(provider.messages.last.role, 'assistant');
      expect(provider.messages.last.content, isEmpty);
      expect(provider.messages.any((m) => m.id == 'a1'), isFalse);

      service.controller
          .add(const ChatResponseChunk(type: 'chunk', content: 'new answer'));
      service.controller.add(const ChatResponseChunk(type: 'done'));
      // Server state after regeneration, picked up by the post-stream reload.
      service.seedMessages('conv-1', [
        _msg('u1', 'user', 'question'),
        _msg('a2', 'assistant', 'new answer'),
      ]);
      await service.controller.close();
      await _pump();
      await _pump();

      expect(provider.isSending, isFalse);
      expect(
        provider.messages.map((m) => m.content),
        ['question', 'new answer'],
      );
    });

    test('is a no-op without a persisted assistant message', () async {
      final service = _FakeChatService();
      service.seedMessages('conv-1', [_msg('u1', 'user', 'question')]);
      final provider = await _openConversation(service);

      await provider.regenerateLastAssistant();

      expect(service.regenerateCalls, isEmpty);
      expect(provider.isSending, isFalse);
      expect(provider.messages, hasLength(1));
    });
  });

  group('editUserMessage', () {
    test('optimistically rewrites the message and drops later ones', () async {
      final service = _FakeChatService();
      service.seedMessages('conv-1', [
        _msg('u1', 'user', 'first question'),
        _msg('a1', 'assistant', 'first answer'),
        _msg('u2', 'user', 'second question'),
        _msg('a2', 'assistant', 'second answer'),
      ]);
      final provider = await _openConversation(service);

      await provider.editUserMessage('u1', 'edited question');

      expect(service.editCalls, [
        (
          conversationId: 'conv-1',
          messageId: 'u1',
          content: 'edited question',
        ),
      ]);
      expect(provider.isSending, isTrue);
      // Everything after the edited message is gone; placeholder appended.
      expect(provider.messages, hasLength(2));
      expect(provider.messages.first.id, 'u1');
      expect(provider.messages.first.content, 'edited question');
      expect(provider.messages.last.role, 'assistant');

      service.controller
          .add(const ChatResponseChunk(type: 'chunk', content: 'fresh answer'));
      service.controller.add(const ChatResponseChunk(type: 'done'));
      service.seedMessages('conv-1', [
        _msg('u1', 'user', 'edited question'),
        _msg('a3', 'assistant', 'fresh answer'),
      ]);
      await service.controller.close();
      await _pump();
      await _pump();

      expect(provider.isSending, isFalse);
      expect(
        provider.messages.map((m) => m.content),
        ['edited question', 'fresh answer'],
      );
    });

    test('refuses to edit an assistant message', () async {
      final service = _FakeChatService();
      service.seedMessages('conv-1', [
        _msg('u1', 'user', 'question'),
        _msg('a1', 'assistant', 'answer'),
      ]);
      final provider = await _openConversation(service);

      await provider.editUserMessage('a1', 'nope');

      expect(service.editCalls, isEmpty);
      expect(provider.messages, hasLength(2));
    });

    test('ignores empty replacement content', () async {
      final service = _FakeChatService();
      service.seedMessages('conv-1', [_msg('u1', 'user', 'question')]);
      final provider = await _openConversation(service);

      await provider.editUserMessage('u1', '   ');

      expect(service.editCalls, isEmpty);
      expect(provider.messages.first.content, 'question');
    });
  });

  group('branchFromMessage', () {
    test('creates the branch, prepends it, and navigates to it', () async {
      final service = _FakeChatService();
      service.seedMessages('conv-1', [
        _msg('u1', 'user', 'question'),
        _msg('a1', 'assistant', 'answer'),
      ]);
      final provider = await _openConversation(service);

      await provider.branchFromMessage('a1');

      expect(
        service.branchCalls,
        [(conversationId: 'conv-1', messageId: 'a1')],
      );
      expect(provider.currentConversation?.id, 'conv-branched');
      expect(provider.conversations.first.id, 'conv-branched');
      expect(provider.error, isNull);
    });

    test('surfaces an error and stays on the current conversation', () async {
      final service = _FakeChatService();
      service.branchError = Exception('boom');
      final provider = await _openConversation(service);

      await provider.branchFromMessage('a1');

      expect(provider.currentConversation?.id, 'conv-1');
      expect(provider.error, contains('Failed to branch conversation'));
    });
  });

  group('togglePin', () {
    test('flips the pinned state and syncs the open conversation', () async {
      final service = _FakeChatService();
      final provider = await _openConversation(service);
      await _pump(); // let the initial sidebar load settle
      expect(provider.currentConversation?.isPinned, isFalse);

      await provider.togglePin('conv-1');

      expect(
        service.updateCalls,
        [(conversationId: 'conv-1', isPinned: true)],
      );
      expect(provider.currentConversation?.isPinned, isTrue);
      expect(provider.conversations.first.isPinned, isTrue);
    });
  });

  group('pending attachments', () {
    test('addAttachments accumulates and clearPendingAttachments resets',
        () async {
      final service = _FakeChatService();
      final provider = await _openConversation(service);
      expect(provider.pendingAttachments, isNull);

      final attachment = ChatAttachment(
        name: 'notes.txt',
        mimeType: 'text/plain',
        type: AttachmentType.document,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.addAttachments([attachment]);
      expect(provider.pendingAttachments, hasLength(1));

      provider.addAttachments([attachment]);
      expect(provider.pendingAttachments, hasLength(2));

      provider.clearPendingAttachments();
      expect(provider.pendingAttachments, isNull);
      expect(notifications, 3);
    });
  });

  group('sendMessage', () {
    test('appends the user message optimistically and streams the reply',
        () async {
      final service = _FakeChatService();
      final provider = await _openConversation(service);

      await provider.sendMessage('hello there');

      expect(service.streamChatCalls, 1);
      expect(provider.isSending, isTrue);
      // User message + assistant placeholder.
      expect(provider.messages, hasLength(2));
      expect(provider.messages.first.role, 'user');
      expect(provider.messages.first.content, 'hello there');

      service.controller
          .add(const ChatResponseChunk(type: 'chunk', content: 'hi!'));
      service.controller.add(const ChatResponseChunk(type: 'done'));
      await _pump();
      expect(provider.messages.last.content, 'hi!');

      await service.controller.close();
      await _pump();
      expect(provider.isSending, isFalse);
    });

    test('ignores sends while a stream is active', () async {
      final service = _FakeChatService();
      final provider = await _openConversation(service);

      await provider.sendMessage('first');
      await provider.sendMessage('second');

      expect(service.streamChatCalls, 1);
      expect(
        provider.messages.where((m) => m.isUser).map((m) => m.content),
        ['first'],
      );
    });

    test('ignores empty messages without attachments', () async {
      final service = _FakeChatService();
      final provider = await _openConversation(service);

      await provider.sendMessage('   ');

      expect(service.streamChatCalls, 0);
      expect(provider.messages, isEmpty);
    });

    test('surfaces a service failure and resets the sending flag', () async {
      final service = _FakeChatService();
      service.streamChatError = Exception('connection refused');
      final provider = await _openConversation(service);

      await provider.sendMessage('hello');

      expect(provider.error, contains('Failed to send message'));
      expect(provider.isSending, isFalse);
    });

    test('an error event mid-stream keeps partial content and stops sending',
        () async {
      final service = _FakeChatService();
      final provider = await _openConversation(service);

      await provider.sendMessage('hello');
      service.controller
          .add(const ChatResponseChunk(type: 'chunk', content: 'partial'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      service.controller
          .add(const ChatResponseChunk(type: 'error', error: 'model exploded'));
      await _pump();

      expect(provider.error, 'model exploded');
      expect(provider.isSending, isFalse);
      expect(provider.messages.last.content, 'partial');

      await service.controller.close();
    });
  });
}
