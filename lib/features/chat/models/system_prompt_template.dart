import 'package:freezed_annotation/freezed_annotation.dart';

part 'system_prompt_template.freezed.dart';
part 'system_prompt_template.g.dart';

/// A reusable system prompt (built-in persona or user-saved custom prompt).
@freezed
class SystemPromptTemplate with _$SystemPromptTemplate {
  const SystemPromptTemplate._();

  const factory SystemPromptTemplate({
    required String id,
    required String name,
    String? description,
    required String content,
    @Default(false) bool isBuiltin,
    required DateTime createdAt,
  }) = _SystemPromptTemplate;

  factory SystemPromptTemplate.fromJson(Map<String, dynamic> json) =>
      _$SystemPromptTemplateFromJson(json);
}
