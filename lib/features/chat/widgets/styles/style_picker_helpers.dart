import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';

/// The capability vocabulary shared by the model rows' badges.
enum StyleCapability {
  vision(Icons.visibility_outlined, 'Vision'),
  tools(Icons.build_outlined, 'Tools'),
  thinking(Icons.psychology_outlined, 'Thinking');

  const StyleCapability(this.icon, this.label);

  final IconData icon;
  final String label;

  /// Tri-state: true/false as reported by the provider, null when unknown.
  bool? of(ModelInfo model) => switch (this) {
    StyleCapability.vision => model.supportsVision,
    StyleCapability.tools => model.supportsTools,
    StyleCapability.thinking => model.supportsThinking,
  };
}

String? normalizeStylePrompt(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

String styleMonogram(String name) =>
    name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

String styleComposition(Style s, String? modelName, String? templateName) => [
  modelName ?? s.modelId,
  if (s.thinkingLevel != null)
    'Thinking ${s.thinkingLevel!.label.toLowerCase()}',
  ?templateName,
].join(' · ');

/// Resolves a system-prompt-template id to its (normalized) content, or null
/// for "no template" / a template that no longer exists.
String? resolveTemplateContent(
  List<SystemPromptTemplate> templates,
  String? templateId,
) {
  if (templateId == null) return null;
  return normalizeStylePrompt(
    templates.where((t) => t.id == templateId).firstOrNull?.content,
  );
}

/// Whether a style should be shown in the picker for [languageCode]. Built-in
/// styles carry a BCP-47 language subtag and only surface in their locale;
/// user-saved styles have a null locale and always show. A null [languageCode]
/// disables filtering so isolated widget tests without [SettingsProvider] keep
/// working unchanged.
bool styleMatchesLocale(Style style, String? languageCode) {
  if (languageCode == null) return true;
  if (!style.isBuiltin || style.locale == null) return true;
  return style.locale == languageCode;
}

/// Resolves the active language code from [SettingsProvider] when present in
/// the widget tree, or null in isolated widget tests.
String? effectiveLanguageCode(BuildContext context) =>
    context.read<SettingsProvider?>()?.effectiveLanguageCode;

bool _styleMatches(
  Style style,
  List<SystemPromptTemplate> templates, {
  required String? modelId,
  required ThinkingLevel? thinkingLevel,
  required String? systemPrompt,
}) {
  return style.modelId == modelId &&
      style.thinkingLevel == thinkingLevel &&
      resolveTemplateContent(templates, style.systemPromptTemplateId) ==
          systemPrompt;
}

/// Named style identity is the base model + prompt persona. Thinking effort
/// is deliberately excluded: the composer exposes it as a fast per-chat
/// override and changing it must not replace a style label with a model name.
bool _styleIdentityMatches(
  Style style,
  List<SystemPromptTemplate> templates, {
  required String? modelId,
  required String? systemPrompt,
}) {
  return style.modelId == modelId &&
      resolveTemplateContent(templates, style.systemPromptTemplateId) ==
          systemPrompt;
}

Style? resolveActiveStyle(
  StyleProvider provider,
  List<Style> visibleStyles,
  List<SystemPromptTemplate> templates, {
  required String? modelId,
  required ThinkingLevel? thinkingLevel,
  required String? systemPrompt,
}) {
  final selected = visibleStyles
      .where((style) => style.id == provider.selectedStyleId)
      .firstOrNull;
  if (selected != null &&
      _styleIdentityMatches(
        selected,
        templates,
        modelId: modelId,
        systemPrompt: systemPrompt,
      )) {
    return selected;
  }

  // Reload recovery: exact resolved settings are the strongest evidence when
  // no compatible explicit identity is available.
  return visibleStyles
      .where(
        (style) => _styleMatches(
          style,
          templates,
          modelId: modelId,
          thinkingLevel: thinkingLevel,
          systemPrompt: systemPrompt,
        ),
      )
      .firstOrNull;
}
