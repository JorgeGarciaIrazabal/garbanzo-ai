import 'package:freezed_annotation/freezed_annotation.dart';

import 'chat_attachment.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// Reads the metadata field from either 'meta' (backend canonical) or
/// 'metadata' (legacy / local) key.
Object? _readMetadata(Map json, String key) =>
    json['meta'] ?? json['metadata'];

/// A single message in a chat conversation.
@freezed
class ChatMessage with _$ChatMessage {
  const ChatMessage._();

  const factory ChatMessage({
    required String id,
    required String role,
    required String content,
    required DateTime createdAt,
    @JsonKey(readValue: _readMetadata) Map<String, dynamic>? metadata,
    @Default([])
    @JsonKey(includeFromJson: false, includeToJson: false)
    List<ChatAttachment> attachments,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';
}

/// A chunk of a streaming chat response.
@freezed
class ChatResponseChunk with _$ChatResponseChunk {
  const ChatResponseChunk._();

  const factory ChatResponseChunk({
    required String type,
    String? content,
    String? error,
    Map<String, dynamic>? metadata,
  }) = _ChatResponseChunk;

  factory ChatResponseChunk.fromJson(Map<String, dynamic> json) =>
      _$ChatResponseChunkFromJson(json);

  bool get isChunk => type == 'chunk';
  bool get isThinking => type == 'thinking';
  bool get isDone => type == 'done';
  bool get isError => type == 'error';
}
