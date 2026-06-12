import 'package:freezed_annotation/freezed_annotation.dart';

part 'model_info.freezed.dart';
part 'model_info.g.dart';

/// Information about an available LLM model.
@freezed
class ModelInfo with _$ModelInfo {
  const factory ModelInfo({
    required String id,
    required String name,
    String? description,
    int? contextLength,
    required String provider,
    // Capability flags reported by the provider; null = unknown.
    bool? supportsTools,
    bool? supportsVision,
    bool? supportsThinking,
  }) = _ModelInfo;

  factory ModelInfo.fromJson(Map<String, dynamic> json) =>
      _$ModelInfoFromJson(json);
}

/// A list of available models.
@freezed
class ModelList with _$ModelList {
  const factory ModelList({
    required List<ModelInfo> models,
  }) = _ModelList;

  factory ModelList.fromJson(Map<String, dynamic> json) =>
      _$ModelListFromJson(json);
}
