/// Information about an available LLM model.
class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final int? contextLength;
  final String provider;

  const ModelInfo({
    required this.id,
    required this.name,
    this.description,
    this.contextLength,
    required this.provider,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      contextLength: json['context_length'] as int?,
      provider: json['provider'] as String,
    );
  }
}

/// A list of available models.
class ModelList {
  final List<ModelInfo> models;

  const ModelList({required this.models});

  factory ModelList.fromJson(Map<String, dynamic> json) {
    return ModelList(
      models: (json['models'] as List<dynamic>)
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
