// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Conversation _$ConversationFromJson(Map<String, dynamic> json) =>
    _Conversation(
      id: json['id'] as String,
      title: json['title'] as String?,
      model: json['model'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      useMemory: json['use_memory'] as bool? ?? true,
      useKnowledgeBase: json['use_knowledge_base'] as bool? ?? true,
      isPinned: json['is_pinned'] as bool? ?? false,
      contextSummary: json['context_summary'] as String?,
      systemPrompt: json['system_prompt'] as String?,
      thinkingLevel: $enumDecodeNullable(
        _$ThinkingLevelEnumMap,
        json['thinking_level'],
        unknownValue: JsonKey.nullForUndefinedEnumValue,
      ),
      enabledTools: (json['enabled_tools'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      messages: (json['messages'] as List<dynamic>?)
          ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMoreMessages: json['has_more_messages'] as bool? ?? false,
      mutedUntil: json['muted_until'] == null
          ? null
          : DateTime.parse(json['muted_until'] as String),
      isPrimary: json['is_primary'] as bool? ?? false,
      activeTopicId: json['active_topic_id'] as String?,
      activeTopic: json['active_topic'] == null
          ? null
          : TopicNode.fromJson(json['active_topic'] as Map<String, dynamic>),
      topicIsPinned: json['topic_is_pinned'] as bool? ?? false,
      contextVersion: (json['context_version'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ConversationToJson(_Conversation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'model': instance.model,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'message_count': instance.messageCount,
      'use_memory': instance.useMemory,
      'use_knowledge_base': instance.useKnowledgeBase,
      'is_pinned': instance.isPinned,
      'context_summary': instance.contextSummary,
      'system_prompt': instance.systemPrompt,
      'thinking_level': _$ThinkingLevelEnumMap[instance.thinkingLevel],
      'enabled_tools': instance.enabledTools,
      'messages': instance.messages,
      'has_more_messages': instance.hasMoreMessages,
      'muted_until': instance.mutedUntil?.toIso8601String(),
      'is_primary': instance.isPrimary,
      'active_topic_id': instance.activeTopicId,
      'active_topic': instance.activeTopic,
      'topic_is_pinned': instance.topicIsPinned,
      'context_version': instance.contextVersion,
    };

const _$ThinkingLevelEnumMap = {
  ThinkingLevel.off: 'off',
  ThinkingLevel.low: 'low',
  ThinkingLevel.medium: 'medium',
  ThinkingLevel.high: 'high',
};

_ConversationList _$ConversationListFromJson(Map<String, dynamic> json) =>
    _ConversationList(
      items: (json['items'] as List<dynamic>)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      pageSize: (json['page_size'] as num).toInt(),
    );

Map<String, dynamic> _$ConversationListToJson(_ConversationList instance) =>
    <String, dynamic>{
      'items': instance.items,
      'total': instance.total,
      'page': instance.page,
      'page_size': instance.pageSize,
    };
