// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_prompt_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SystemPromptTemplate _$SystemPromptTemplateFromJson(
  Map<String, dynamic> json,
) => _SystemPromptTemplate(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  content: json['content'] as String,
  isBuiltin: json['is_builtin'] as bool? ?? false,
  createdAt: DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$SystemPromptTemplateToJson(
  _SystemPromptTemplate instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'content': instance.content,
  'is_builtin': instance.isBuiltin,
  'created_at': instance.createdAt.toIso8601String(),
};
