/// A model whose visibility is controlled by admins.
class AdminModel {
  final String modelId;
  final bool isEnabled;
  final bool isNew;
  final String? name;
  final String? description;
  final int? contextLength;
  final DateTime? updatedAt;

  const AdminModel({
    required this.modelId,
    this.isEnabled = true,
    this.isNew = false,
    this.name,
    this.description,
    this.contextLength,
    this.updatedAt,
  });

  factory AdminModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return AdminModel(
      modelId: (json['model_id'] as String?) ?? '',
      isEnabled: json['is_enabled'] as bool? ?? true,
      isNew: json['is_new'] as bool? ?? false,
      name: json['name'] as String?,
      description: json['description'] as String?,
      contextLength: (json['context_length'] as num?)?.toInt(),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  AdminModel copyWith({
    String? modelId,
    bool? isEnabled,
    bool? isNew,
    String? name,
    String? description,
    int? contextLength,
    DateTime? updatedAt,
  }) {
    return AdminModel(
      modelId: modelId ?? this.modelId,
      isEnabled: isEnabled ?? this.isEnabled,
      isNew: isNew ?? this.isNew,
      name: name ?? this.name,
      description: description ?? this.description,
      contextLength: contextLength ?? this.contextLength,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}