import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';

part 'style.freezed.dart';
part 'style.g.dart';

/// A saved style: a named bundle of model + thinking level + system prompt
/// template. Applying one configures a conversation in a single tap.
@freezed
abstract class Style with _$Style {
  const factory Style({
    required String id,
    required String name,
    required String modelId,
    // null = provider default ("Auto"): thinking auto-enables when the
    // model supports it.
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    ThinkingLevel? thinkingLevel,
    // References a SystemPromptTemplate; null = no persona. The backend
    // nulls this out (not cascades) when the template is deleted.
    String? systemPromptTemplateId,
    // Seeds new conversations. At most one style per user is default.
    @Default(false) bool isDefault,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Style;

  factory Style.fromJson(Map<String, dynamic> json) => _$StyleFromJson(json);
}
