import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';

Conversation _thread(String id) => Conversation(
  id: id, model: 'test-model', createdAt: DateTime(2026), updatedAt: DateTime(2026),
  activeTopicId: 'topic-1', messages: [
    ChatMessage(id: '$id-history', role: 'assistant', content: 'Saved history for $id', createdAt: DateTime(2026)),
  ],
);

class _Service extends ChatService {
  _Service() : super.forTesting();
  final stream = StreamController<ChatResponseChunk>();
  final stops = <String>[];
  final sends = <String>[];
  final clientResults = <(String, Map<String, dynamic>)>[];
  final delayed = <String, Completer<Conversation>>{};

  @override
  Future<ConversationList> listConversations({int page = 1, int pageSize = 20, bool silent = false}) async =>
      ConversationList(items: [_thread('first')], total: 1, page: page, pageSize: pageSize);

  @override
  Future<Conversation> getConversation(String conversationId, {int? messageLimit, bool silent = false}) async =>
      delayed[conversationId]?.future ?? _thread(conversationId);

  @override
  Future<void> stopStreaming(String conversationId) async { stops.add(conversationId); }

  @override
  Stream<ChatResponseChunk> streamChatResponse(String conversationId, String message, {
    List<ChatAttachment> attachments = const [], double temperature = 0.7, int? maxTokens,
    double? topP, bool hasClientFolder = false, String? clientFolderLabel, String? talkModeInstruction,
  }) { sends.add(conversationId); return stream.stream; }

  @override
  Future<void> postClientToolResult(String conversationId, Map<String, dynamic> payload) async {
    clientResults.add((conversationId, payload));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('topic start opens a separate thread while the old reply can finish', () async {
    final service = _Service();
    final chat = ChatProvider(chatService: service);
    await chat.loadConversation('first');
    await chat.sendMessage('Keep working');
    expect(chat.isSending, isTrue);
    await chat.applyTopicSwitch(TopicSwitchResponse(
      conversationId: 'second', contextVersion: 0, sessionEpoch: 0, archived: false,
      retainedItems: const [], contextStatus: TopicContextStatus.ready,
      idempotencyKey: 'start-second', topic: TopicSwitchTopic(id: 'topic-1', label: 'Topic', pinned: true),
    ));
    expect(service.stops, isEmpty);
    expect(chat.currentConversation?.id, 'second');
    expect(chat.currentConversation?.isPrimary, isFalse);
    expect(chat.isSending, isFalse);
    expect(chat.messages.single.content, 'Saved history for second');
    expect(chat.conversations.any((conversation) => conversation.id == 'second'), isTrue);
    service.stream.add(const ChatResponseChunk(type: 'client_tool_request', metadata: {
      'client_tool_request': {'tool_call_id': 'late-tool', 'tool_name': 'read_file', 'args': {'path': 'file.txt'}},
    }));
    await Future<void>.delayed(Duration.zero);
    expect(service.clientResults.single.$1, 'first');
    expect(service.clientResults.single.$2['tool_call_id'], 'late-tool');
    expect(chat.messages.single.content, 'Saved history for second');
    await chat.loadConversation('first');
    expect(chat.messages.single.id, 'first-history');
    chat.dispose();
    await service.stream.close();
  });

  test('a slower old load cannot replace the most recently opened thread', () async {
    final service = _Service();
    service.delayed['slow'] = Completer<Conversation>();
    final chat = ChatProvider(chatService: service);
    final slowLoad = chat.loadConversation('slow');
    expect(chat.isSending, isTrue);
    await chat.sendMessage('Do not send to the previous thread');
    expect(service.sends, isEmpty);
    await chat.loadConversation('fast');
    service.delayed['slow']!.complete(_thread('slow'));
    await slowLoad;
    expect(chat.currentConversation?.id, 'fast');
    expect(chat.messages.single.id, 'fast-history');
    expect(chat.isSending, isFalse);
    chat.dispose();
  });

  test('topic start adopts the folder selected for the pending conversation', () async {
    final service = _Service();
    final chat = ChatProvider(chatService: service);
    await chat.loadConversation('first');
    await chat.attachClientFolder(null, '/tmp/pending-topic-folder');
    await chat.applyTopicSwitch(TopicSwitchResponse(
      conversationId: 'second', contextVersion: 0, sessionEpoch: 0, archived: false,
      retainedItems: const [], contextStatus: TopicContextStatus.ready,
      idempotencyKey: 'start-folder', topic: TopicSwitchTopic(id: 'topic-1', label: 'Topic', pinned: true),
    ));
    expect(chat.clientFolderFor('second'), '/tmp/pending-topic-folder');
    expect(chat.clientFolderFor(null), isNull);
    expect(chat.clientFolderFor('first'), isNull);
    chat.dispose();
  });

  test('Stop during navigation leaves the destination load intact', () async {
    final service = _Service();
    final chat = ChatProvider(chatService: service);
    await chat.loadConversation('first');
    await chat.sendMessage('Keep working in the original thread');
    expect(chat.canStopGeneration, isTrue);
    service.delayed['second'] = Completer<Conversation>();
    final navigation = chat.loadConversation('second');
    expect(chat.isSending, isTrue);
    expect(chat.canStopGeneration, isFalse);
    await chat.stopStreaming();
    expect(service.stops, isEmpty);
    service.delayed['second']!.complete(_thread('second'));
    await navigation;
    expect(chat.currentConversation?.id, 'second');
    expect(chat.isSending, isFalse);
    expect(chat.canStopGeneration, isFalse);
    chat.dispose();
    await service.stream.close();
  });
}
