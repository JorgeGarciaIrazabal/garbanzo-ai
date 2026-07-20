import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

/// Fake ChatService that plays back a scripted chunk stream and lets the
/// test control when each chunk is delivered.
class _FakeChatService extends ChatService {
  _FakeChatService() : super.forTesting();

  final StreamController<ChatResponseChunk> controller =
      StreamController<ChatResponseChunk>();
  bool stopCalled = false;

  final _conversation = Conversation(
    id: 'conv-1',
    title: 'Test',
    model: 'llama3.2',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    messages: const [],
  );

  // Set by tests that want a later reload (post-error, post-done) to surface
  // content the backend persisted independently of the live stream.
  Conversation? reloadedConversation;

  @override
  Future<ConversationList> listConversations(
      {int page = 1, int pageSize = 50}) async {
    return ConversationList(
        items: [_conversation], total: 1, page: 1, pageSize: 50);
  }

  @override
  Future<Conversation> getConversation(
    String conversationId, {
    int? messageLimit,
  }) async {
    return reloadedConversation ?? _conversation;
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
  }) {
    return controller.stream;
  }

  @override
  Future<void> stopStreaming(String conversationId) async {
    stopCalled = true;
  }

  final List<String> deletedIds = [];

  @override
  Future<void> deleteConversation(String conversationId) async {
    deletedIds.add(conversationId);
  }
}

Future<ChatProvider> _providerWithOpenConversation(
    _FakeChatService service) async {
  final provider =
      ChatProvider(selectedModelId: 'llama3.2', chatService: service);
  await provider.loadConversation('conv-1');
  return provider;
}

void main() {
  group('ChatProvider streaming channel', () {
    test('content chunks update streamingMessage without notifying listeners',
        () async {
      final service = _FakeChatService();
      final provider = await _providerWithOpenConversation(service);

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.sendMessage('hi');
      // Placeholder added (structural) — listeners notified, stream id set.
      final structuralBaseline = notifications;
      expect(provider.streamingMessageId, isNotNull);
      expect(provider.messages.last.role, 'assistant');
      expect(provider.messages.last.content, isEmpty);

      service.controller
          .add(const ChatResponseChunk(type: 'chunk', content: 'hel'));
      service.controller
          .add(const ChatResponseChunk(type: 'chunk', content: 'lo'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Content flowed through the ValueNotifier, not notifyListeners.
      expect(notifications, structuralBaseline);
      expect(provider.streamingMessage.value?.content, 'hello');
      // The list copy still holds the empty placeholder (sync happens on
      // structural events only).
      expect(provider.messages.last.content, isEmpty);

      // Per-iteration done commits content + metadata into the list.
      service.controller.add(const ChatResponseChunk(
          type: 'done', metadata: {'tokens_generated': 2}));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, greaterThan(structuralBaseline));
      expect(provider.messages.last.content, 'hello');
      expect(provider.messages.last.metadata?['tokens_generated'], 2);

      await service.controller.close();
      await Future<void>.delayed(Duration.zero);
      expect(provider.isSending, isFalse);
      expect(provider.streamingMessageId, isNull);
      expect(provider.streamingMessage.value, isNull);
    });

    test('stopStreaming keeps already-streamed content, marked stopped',
        () async {
      final service = _FakeChatService();
      final provider = await _providerWithOpenConversation(service);

      await provider.sendMessage('hi');
      service.controller
          .add(const ChatResponseChunk(type: 'chunk', content: 'partial answ'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await provider.stopStreaming();

      expect(service.stopCalled, isTrue);
      expect(provider.isSending, isFalse);
      expect(provider.streamingMessageId, isNull);
      // The partial content was committed to the list, not lost, and is
      // flagged as interrupted.
      expect(provider.messages.last.content, 'partial answ');
      expect(provider.messages.last.metadata?['stopped'], isTrue);
    });

    test(
        'stream error reloads the conversation to recover server-persisted '
        'content (B-01)', () async {
      final service = _FakeChatService();
      final provider = await _providerWithOpenConversation(service);

      // Simulates the backend having persisted a reply (e.g. up to the
      // point of a client disconnect) despite the stream itself erroring.
      service.reloadedConversation = Conversation(
        id: 'conv-1',
        title: 'Test',
        model: 'llama3.2',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        messages: [
          ChatMessage(
            id: 'm1',
            role: 'assistant',
            content: 'Recovered from disconnect',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );

      await provider.sendMessage('hi');
      service.controller
          .addError(Exception('Connection closed while receiving data'));
      await Future<void>.delayed(Duration.zero);

      expect(provider.error, contains('Streaming error'));
      expect(provider.isSending, isFalse);
      expect(
        provider.messages.any((m) => m.content == 'Recovered from disconnect'),
        isTrue,
      );
    });

    test('undo within the window restores the conversation without API call',
        () async {
      final service = _FakeChatService();
      final provider = await _providerWithOpenConversation(service);
      expect(provider.conversations, hasLength(1));

      await provider.deleteConversation('conv-1');
      expect(provider.conversations, isEmpty);
      expect(service.deletedIds, isEmpty); // API deferred

      provider.undoDeleteConversation('conv-1');
      expect(provider.conversations, hasLength(1));
      expect(provider.conversations.first.id, 'conv-1');

      // The undo cancelled the pending timer — no API call ever fires.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.deletedIds, isEmpty);
    });

    test('delete commits to the API after the undo window', () async {
      final service = _FakeChatService();
      final provider = await _providerWithOpenConversation(service);

      await provider.deleteConversation('conv-1');
      expect(service.deletedIds, isEmpty);

      // Provider disposal flushes pending deletes immediately, which is the
      // same code path the timer takes — assert via dispose to avoid a 6s
      // wall-clock wait.
      provider.dispose();
      expect(service.deletedIds, ['conv-1']);
    });

    test('tool_execution updates land on the matching tool_call message',
        () async {
      final service = _FakeChatService();
      final provider = await _providerWithOpenConversation(service);
      await provider.sendMessage('hi');

      service.controller.add(ChatResponseChunk(
        type: 'tool_call',
        toolCalls: [
          const ToolCall(id: 'call-7', name: 'search', arguments: {}),
        ],
      ));
      await Future<void>.delayed(Duration.zero);

      service.controller.add(const ChatResponseChunk(
        type: 'tool_execution',
        metadata: {
          'tool_execution': {
            'tool_call_id': 'call-7',
            'tool_name': 'search',
            'status': 'started',
          },
        },
      ));
      await Future<void>.delayed(Duration.zero);

      var toolMsg = provider.messages
          .firstWhere((m) => m.id == 'temp-tool-call-call-7');
      expect(toolMsg.metadata?['tool_execution']?['status'], 'started');
      // The original call payload is preserved alongside the status.
      expect(toolMsg.metadata?['tool_calls'], isNotNull);

      service.controller.add(const ChatResponseChunk(
        type: 'tool_execution',
        metadata: {
          'tool_execution': {
            'tool_call_id': 'call-7',
            'tool_name': 'search',
            'status': 'finished',
            'duration_ms': 2300,
          },
        },
      ));
      await Future<void>.delayed(Duration.zero);

      toolMsg = provider.messages
          .firstWhere((m) => m.id == 'temp-tool-call-call-7');
      expect(toolMsg.metadata?['tool_execution']?['status'], 'finished');
      expect(toolMsg.metadata?['tool_execution']?['duration_ms'], 2300);

      await service.controller.close();
    });

    test('throttle coalesces rapid chunks but flushes the trailing state',
        () async {
      final service = _FakeChatService();
      final provider = await _providerWithOpenConversation(service);

      var pushes = 0;
      await provider.sendMessage('hi');
      provider.streamingMessage.addListener(() => pushes++);

      // 20 chunks back-to-back — far faster than the 80ms push interval.
      for (var i = 0; i < 20; i++) {
        service.controller
            .add(const ChatResponseChunk(type: 'chunk', content: 'x'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Coalesced into a handful of pushes, but nothing was dropped.
      expect(pushes, lessThan(20));
      expect(provider.streamingMessage.value?.content, 'x' * 20);
    });
  });
}
