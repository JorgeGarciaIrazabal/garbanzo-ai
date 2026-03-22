// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MemoryImpl _$$MemoryImplFromJson(Map<String, dynamic> json) => _$MemoryImpl(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  content: json['content'] as String,
  sourceConversationId: json['source_conversation_id'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  isActive: json['is_active'] as bool,
);

Map<String, dynamic> _$$MemoryImplToJson(_$MemoryImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'content': instance.content,
      'source_conversation_id': instance.sourceConversationId,
      'created_at': instance.createdAt.toIso8601String(),
      'is_active': instance.isActive,
    };
