// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ConversationImpl _$$ConversationImplFromJson(Map<String, dynamic> json) =>
    _$ConversationImpl(
      id: json['id'] as String,
      title: json['title'] as String?,
      model: json['model'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      messages: (json['messages'] as List<dynamic>?)
          ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$ConversationImplToJson(_$ConversationImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'model': instance.model,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'message_count': instance.messageCount,
      'messages': instance.messages,
    };

_$ConversationListImpl _$$ConversationListImplFromJson(
  Map<String, dynamic> json,
) => _$ConversationListImpl(
  items: (json['items'] as List<dynamic>)
      .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
      .toList(),
  total: (json['total'] as num).toInt(),
  page: (json['page'] as num).toInt(),
  pageSize: (json['page_size'] as num).toInt(),
);

Map<String, dynamic> _$$ConversationListImplToJson(
  _$ConversationListImpl instance,
) => <String, dynamic>{
  'items': instance.items,
  'total': instance.total,
  'page': instance.page,
  'page_size': instance.pageSize,
};
