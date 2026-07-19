import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';

part 'style.freezed.dart';
part 'style.g.dart';

/// A saved style: a named bundle of model + thinking level + system prompt
/// template. Applying one configures a conversation in a single tap.
///
/// Built-in styles (isBuiltin) ship with the app, are shared across all
/// users, and are read-only — the backend refuses PATCH/DELETE on them.
/// `locale` carries a BCP-47 tag for built-ins so the picker surfaces them
/// in the user's language; null for user-saved styles (language-neutral).
@freezed
abstract class Style with _$Style {
  const factory Style({
    required String id,
    required String name,
    String? description,
    required String modelId,
    // null = provider default ("Auto"): thinking auto-enables when the
    // model supports it.
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    ThinkingLevel? thinkingLevel,
    // References a SystemPromptTemplate; null = no persona. The backend
    // nulls this out (not cascades) when the template is deleted.
    String? systemPromptTemplateId,
    @Default(false) bool isBuiltin,
    String? locale,
    // Seeds new conversations. At most one style per user is default.
    @Default(false) bool isDefault,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Style;

  factory Style.fromJson(Map<String, dynamic> json) => _$StyleFromJson(json);
}
