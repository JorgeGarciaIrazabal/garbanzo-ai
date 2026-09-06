import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';

part 'model_info.freezed.dart';
part 'model_info.g.dart';

extension ModelInfoThinkingLevels on ModelInfo {
  /// Normalized UI positions supported by this model.
  ///
  /// Older providers report only `supportsThinking`; retain compatibility by
  /// exposing all normalized positions when that flag is explicitly true.
  /// Unknown or explicitly unsupported models keep the control disabled.
  List<ThinkingLevel> get supportedThinkingLevels {
    if (supportsThinking != true) return const <ThinkingLevel>[];
    return thinkingLevels ?? ThinkingLevel.values;
  }
}

/// Information about an available LLM model.
@freezed
abstract class ModelInfo with _$ModelInfo {
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
    List<ThinkingLevel>? thinkingLevels,
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    ThinkingLevel? defaultThinkingLevel,
  }) = _ModelInfo;

  factory ModelInfo.fromJson(Map<String, dynamic> json) =>
      _$ModelInfoFromJson(json);
}

/// A list of available models.
@freezed
abstract class ModelList with _$ModelList {
  const factory ModelList({
    required List<ModelInfo> models,
    // Server-recommended default model id, if the backend provides one.
    String? defaultModel,
  }) = _ModelList;

  factory ModelList.fromJson(Map<String, dynamic> json) =>
      _$ModelListFromJson(json);
}
