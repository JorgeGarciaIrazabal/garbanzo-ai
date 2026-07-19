// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'style.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Style _$StyleFromJson(Map<String, dynamic> json) => _Style(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  modelId: json['model_id'] as String,
  thinkingLevel: $enumDecodeNullable(
    _$ThinkingLevelEnumMap,
    json['thinking_level'],
    unknownValue: JsonKey.nullForUndefinedEnumValue,
  ),
  systemPromptTemplateId: json['system_prompt_template_id'] as String?,
  isBuiltin: json['is_builtin'] as bool? ?? false,
  locale: json['locale'] as String?,
  isDefault: json['is_default'] as bool? ?? false,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$StyleToJson(_Style instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'model_id': instance.modelId,
  'thinking_level': _$ThinkingLevelEnumMap[instance.thinkingLevel],
  'system_prompt_template_id': instance.systemPromptTemplateId,
  'is_builtin': instance.isBuiltin,
  'locale': instance.locale,
  'is_default': instance.isDefault,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
};

const _$ThinkingLevelEnumMap = {
  ThinkingLevel.off: 'off',
  ThinkingLevel.low: 'low',
  ThinkingLevel.medium: 'medium',
  ThinkingLevel.high: 'high',
};
