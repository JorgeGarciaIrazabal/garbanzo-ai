// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ModelInfo _$ModelInfoFromJson(Map<String, dynamic> json) => _ModelInfo(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  contextLength: (json['context_length'] as num?)?.toInt(),
  provider: json['provider'] as String,
  supportsTools: json['supports_tools'] as bool?,
  supportsVision: json['supports_vision'] as bool?,
  supportsThinking: json['supports_thinking'] as bool?,
);

Map<String, dynamic> _$ModelInfoToJson(_ModelInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'context_length': instance.contextLength,
      'provider': instance.provider,
      'supports_tools': instance.supportsTools,
      'supports_vision': instance.supportsVision,
      'supports_thinking': instance.supportsThinking,
    };

_ModelList _$ModelListFromJson(Map<String, dynamic> json) => _ModelList(
  models: (json['models'] as List<dynamic>)
      .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ModelListToJson(_ModelList instance) =>
    <String, dynamic>{'models': instance.models};
