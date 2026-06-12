// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ModelInfoImpl _$$ModelInfoImplFromJson(Map<String, dynamic> json) =>
    _$ModelInfoImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      contextLength: (json['context_length'] as num?)?.toInt(),
      provider: json['provider'] as String,
      supportsTools: json['supports_tools'] as bool?,
      supportsVision: json['supports_vision'] as bool?,
      supportsThinking: json['supports_thinking'] as bool?,
    );

Map<String, dynamic> _$$ModelInfoImplToJson(_$ModelInfoImpl instance) =>
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

_$ModelListImpl _$$ModelListImplFromJson(Map<String, dynamic> json) =>
    _$ModelListImpl(
      models: (json['models'] as List<dynamic>)
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$ModelListImplToJson(_$ModelListImpl instance) =>
    <String, dynamic>{'models': instance.models};
