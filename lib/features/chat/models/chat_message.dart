import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// Reads the metadata field from either 'meta' (backend canonical) or
/// 'metadata' (legacy / local) key.
Object? _readMetadata(Map json, String key) => json['meta'] ?? json['metadata'];

/// A single message in a chat conversation.
@freezed
abstract class ChatMessage with _$ChatMessage {
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

  /// The action proposal carried by a proposal tool's result, if any —
  /// `{type, summary, payload}` as produced by the backend's proposal tools
  /// (create_room, set_conversation_style). Lives inside the persisted
  /// tool_result meta so it survives reloads; the streaming path builds the
  /// same shape.
  Map<String, dynamic>? get actionProposal {
    final tr = metadata?['tool_result'];
    if (tr is! Map) return null;
    final result = tr['result'];
    if (result is! Map) return null;
    final proposal = result['proposal'];
    if (proposal is! Map) return null;
    return Map<String, dynamic>.from(proposal);
  }

  /// The tool_call_id of a tool_result message (used to key proposal
  /// confirm/dismiss decisions).
  String? get toolCallId {
    final tr = metadata?['tool_result'];
    return tr is Map ? tr['tool_call_id'] as String? : null;
  }
}

/// A single tool invocation requested by the assistant.
@freezed
abstract class ToolCall with _$ToolCall {
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
abstract class ToolResult with _$ToolResult {
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
abstract class ChatResponseChunk with _$ChatResponseChunk {
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

  /// Structured proposal from a proposal tool. The card itself renders from
  /// the tool_result message (which carries the same proposal and persists);
  /// this chunk type exists as an explicit stream-level signal.
  bool get isActionProposal => type == 'action_proposal';

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

  /// The backend asking this desktop client to serve a folder read
  /// (idea 17). Carries {tool_call_id, tool_name, args:{path}}.
  bool get isClientToolRequest => type == 'client_tool_request';

  Map<String, dynamic>? get clientToolRequest {
    final raw = metadata?['client_tool_request'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
