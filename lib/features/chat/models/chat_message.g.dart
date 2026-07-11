// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => _ChatMessage(
  id: json['id'] as String,
  role: json['role'] as String,
  content: json['content'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  metadata: _readMetadata(json, 'metadata') as Map<String, dynamic>?,
);

Map<String, dynamic> _$ChatMessageToJson(_ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': instance.role,
      'content': instance.content,
      'created_at': instance.createdAt.toIso8601String(),
      'metadata': instance.metadata,
    };

_ToolCall _$ToolCallFromJson(Map<String, dynamic> json) => _ToolCall(
  id: json['id'] as String,
  name: json['name'] as String,
  arguments: json['arguments'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$ToolCallToJson(_ToolCall instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'arguments': instance.arguments,
};

_ToolResult _$ToolResultFromJson(Map<String, dynamic> json) => _ToolResult(
  toolCallId: json['tool_call_id'] as String,
  toolName: json['tool_name'] as String,
  result: json['result'],
);

Map<String, dynamic> _$ToolResultToJson(_ToolResult instance) =>
    <String, dynamic>{
      'tool_call_id': instance.toolCallId,
      'tool_name': instance.toolName,
      'result': instance.result,
    };

_ChatResponseChunk _$ChatResponseChunkFromJson(Map<String, dynamic> json) =>
    _ChatResponseChunk(
      type: json['type'] as String,
      content: json['content'] as String?,
      error: json['error'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      toolCalls: (json['tool_calls'] as List<dynamic>?)
          ?.map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
          .toList(),
      toolResult: json['tool_result'] == null
          ? null
          : ToolResult.fromJson(json['tool_result'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ChatResponseChunkToJson(_ChatResponseChunk instance) =>
    <String, dynamic>{
      'type': instance.type,
      'content': instance.content,
      'error': instance.error,
      'metadata': instance.metadata,
      'tool_calls': instance.toolCalls,
      'tool_result': instance.toolResult,
    };
