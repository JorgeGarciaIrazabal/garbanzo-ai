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
  bool get isToolCall => role == 'tool_call';
  bool get isToolResult => role == 'tool_result';
}

/// A single tool invocation requested by the assistant.
@freezed
class ToolCall with _$ToolCall {
  const ToolCall._();

  const factory ToolCall({
    required String id,
    required String name,
    Map<String, dynamic>? arguments,
  }) = _ToolCall;

  factory ToolCall.fromJson(Map<String, dynamic> json) =>
      _$ToolCallFromJson(json);
}

/// The result of a single tool invocation.
@freezed
class ToolResult with _$ToolResult {
  const ToolResult._();

  const factory ToolResult({
    required String toolCallId,
    required String toolName,
    dynamic result,
  }) = _ToolResult;

  factory ToolResult.fromJson(Map<String, dynamic> json) =>
      _$ToolResultFromJson(json);
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
    List<ToolCall>? toolCalls,
    ToolResult? toolResult,
  }) = _ChatResponseChunk;

  factory ChatResponseChunk.fromJson(Map<String, dynamic> json) =>
      _$ChatResponseChunkFromJson(json);

  bool get isChunk => type == 'chunk';
  bool get isThinking => type == 'thinking';
  bool get isDone => type == 'done';
  bool get isError => type == 'error';
  bool get isToolCall => type == 'tool_call';
  bool get isToolResult => type == 'tool_result';
  bool get isToolExecution => type == 'tool_execution';

  /// Live tool-progress payload ({tool_call_id, tool_name, status,
  /// duration_ms?}) carried by `tool_execution` chunks.
  Map<String, dynamic>? get toolExecution {
    final raw = metadata?['tool_execution'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
