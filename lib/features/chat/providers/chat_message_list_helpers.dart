import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';

/// Pure list/message transformations and bookmark epoch tracking used by
/// [ChatProvider] so the provider focuses on session and stream orchestration.
class MessageStarController {
  final Set<({String conversationId, String messageId})> _updates = {};
  int _epoch = 0;
  final Map<
    ({String conversationId, String messageId}),
    ({int epoch, bool isStarred})
  >
  _confirmed = {};

  int get epoch => _epoch;

  bool isUpdating(String? conversationId, String messageId) => _updates
      .contains((conversationId: conversationId ?? '', messageId: messageId));

  bool hasPendingFor(String conversationId) =>
      _updates.any((key) => key.conversationId == conversationId);

  /// An explicit navigation GET may have read its snapshot before an in-flight
  /// PATCH committed. Keep just the newer confirmed star, retaining server text.
  ChatMessage mergeConfirmed(
    String conversationId,
    ChatMessage message,
    int readEpoch,
  ) {
    final saved =
        _confirmed[(conversationId: conversationId, messageId: message.id)];
    return saved != null && saved.epoch > readEpoch
        ? message.copyWith(isStarred: saved.isStarred)
        : message;
  }

  Future<bool> setStar({
    required ChatService chatService,
    required Conversation? conversation,
    required List<ChatMessage> messages,
    required String messageId,
    required bool isStarred,
    required bool isSending,
    required bool Function() isDisposed,
    required Conversation? Function() currentConversation,
    required void Function() onBeforeRequest,
    required void Function(bool saved) onConfirmedVisible,
    required void Function(Object error) onErrorVisible,
    required void Function() onFinallyNotify,
  }) async {
    final message = messages.where((m) => m.id == messageId).firstOrNull;
    if (isDisposed() ||
        conversation == null ||
        isSending ||
        message == null ||
        messageId.startsWith('temp-') ||
        (!message.isUser && !message.isAssistant)) {
      return false;
    }
    final key = (conversationId: conversation.id, messageId: messageId);
    if (!_updates.add(key)) return false;
    _epoch++;
    onBeforeRequest();

    bool stillVisible() =>
        !isDisposed() &&
        currentConversation()?.id == conversation.id &&
        currentConversation()?.sessionEpoch == conversation.sessionEpoch;

    try {
      final saved = await chatService.setMessageStar(
        conversation.id,
        messageId,
        isStarred: isStarred,
      );
      if (!isDisposed()) {
        _confirmed[key] = (epoch: ++_epoch, isStarred: saved);
      }
      if (stillVisible()) {
        onConfirmedVisible(saved);
      }
      return true;
    } catch (e) {
      if (stillVisible()) {
        onErrorVisible(e);
      }
      return false;
    } finally {
      _updates.remove(key);
      if (!isDisposed()) {
        _epoch++;
        onFinallyNotify();
      }
    }
  }
}

List<ChatMessage> upsertMessageInList(
  List<ChatMessage> messages,
  ChatMessage message,
) {
  final existingIndex = messages.indexWhere((m) => m.id == message.id);
  if (existingIndex >= 0) {
    final copy = List<ChatMessage>.from(messages);
    copy[existingIndex] = message;
    return copy;
  }
  return [...messages, message];
}

List<ChatMessage> insertMessagesBeforeAnchor(
  List<ChatMessage> messages,
  String anchorId,
  List<ChatMessage> extra,
) {
  if (extra.isEmpty) return messages;
  final idx = messages.indexWhere((m) => m.id == anchorId);
  if (idx < 0) return [...messages, ...extra];
  return [...messages.sublist(0, idx), ...extra, ...messages.sublist(idx)];
}

List<ChatMessage> buildTempToolCallMessages(List<ToolCall> calls) => [
  for (final c in calls)
    ChatMessage(
      id: 'temp-tool-call-${c.id}',
      role: 'tool_call',
      content: c.name,
      createdAt: DateTime.now(),
      metadata: {
        'tool_calls': [
          {'id': c.id, 'name': c.name, 'arguments': c.arguments ?? const {}},
        ],
      },
    ),
];

ChatMessage? buildTempToolResultMessage(ToolResult? result) {
  if (result == null) return null;
  return ChatMessage(
    id: 'temp-tool-result-${result.toolCallId}',
    role: 'tool_result',
    content: result.toolName,
    createdAt: DateTime.now(),
    metadata: {
      'tool_result': {
        'tool_call_id': result.toolCallId,
        'tool_name': result.toolName,
        'result': result.result,
      },
    },
  );
}

ChatMessage buildStreamingAssistantMessage(
  String id,
  String content,
  String thinking,
  Map<String, dynamic>? doneMetadata,
) {
  final meta = <String, dynamic>{
    if (thinking.isNotEmpty) 'thinking': thinking,
    ...?doneMetadata,
  };
  return ChatMessage(
    id: id,
    role: 'assistant',
    content: content,
    createdAt: DateTime.now(),
    metadata: meta.isEmpty ? null : meta,
  );
}

/// Restore [ChatAttachment] objects from the metadata stored by the backend.
List<ChatMessage> hydrateMessageAttachments(List<ChatMessage> messages) {
  return messages.map((msg) {
    final raw = msg.metadata?['attachments'];
    if (raw is! List || raw.isEmpty) return msg;
    final attachments = raw
        .whereType<Map<String, dynamic>>()
        .map(ChatAttachment.fromMetadata)
        .toList();
    return msg.copyWith(attachments: attachments);
  }).toList();
}

String stripAttachedFileMarker(String content) {
  const marker = '\n\n[Attached file: ';
  final idx = content.indexOf(marker);
  return idx < 0 ? content : content.substring(0, idx);
}

Map<String, dynamic> extractDynamicEventPayload(ChatResponseChunk chunk) {
  final metadata = chunk.metadata ?? const <String, dynamic>{};
  final nested = metadata[chunk.type] ?? metadata['payload'];
  if (nested is Map<String, dynamic>) return nested;
  if (nested is Map) {
    return nested.map((key, value) => MapEntry(key.toString(), value));
  }
  return metadata;
}

const _connectionHints = [
  'connection closed',
  'connection error',
  'connection refused',
  'failed host lookup',
  'network is unreachable',
  'software caused connection abort',
];

bool isStreamConnectionError(Object e) {
  if (e is ChatException) return e.kind == 'connection';
  final lower = '$e'.toLowerCase();
  return _connectionHints.any(lower.contains);
}

String friendlyStreamError(Object e) {
  if (e is ChatException) {
    return switch (e.kind) {
      'connection' =>
        'Couldn\'t reach the AI service. Check your connection and try again.',
      'unavailable' =>
        'The AI service is temporarily unavailable. Please try again in a moment.',
      'server' => 'The server encountered an error. Please try again.',
      _ => e.detail != null ? 'Chat error: ${e.detail}' : 'Chat error.',
    };
  }
  if (isStreamConnectionError(e)) {
    return 'Couldn\'t reach the AI service. Check your connection and try again.';
  }
  return 'Streaming error: $e';
}

TopicNode topicNodeFromSwitched(
  TopicSwitchTopic switched, {
  required TopicContextStatus contextStatus,
}) => TopicNode(
  id: switched.id,
  label: switched.label,
  origin: TopicOrigin.history,
  parentId: switched.parentId,
  parentLabel: switched.parentLabel,
  description: switched.description,
  contextStatus: contextStatus,
  combinedTopics: switched.combinedTopics,
);
