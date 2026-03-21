// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ChatMessageImpl _$$ChatMessageImplFromJson(Map<String, dynamic> json) =>
    _$ChatMessageImpl(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      metadata: _readMetadata(json, 'metadata') as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$ChatMessageImplToJson(_$ChatMessageImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': instance.role,
      'content': instance.content,
      'created_at': instance.createdAt.toIso8601String(),
      'metadata': instance.metadata,
    };

_$ChatResponseChunkImpl _$$ChatResponseChunkImplFromJson(
  Map<String, dynamic> json,
) => _$ChatResponseChunkImpl(
  type: json['type'] as String,
  content: json['content'] as String?,
  error: json['error'] as String?,
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$$ChatResponseChunkImplToJson(
  _$ChatResponseChunkImpl instance,
) => <String, dynamic>{
  'type': instance.type,
  'content': instance.content,
  'error': instance.error,
  'metadata': instance.metadata,
};
