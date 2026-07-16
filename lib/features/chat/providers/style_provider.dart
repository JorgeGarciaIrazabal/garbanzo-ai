import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/services/style_service.dart';
import 'package:garbanzo_ai/features/chat/services/system_prompt_service.dart';

/// Manages the user's saved styles plus the *pending* new-conversation
/// settings the style picker composes (thinking level + system prompt).
///
/// Mirrors the [ModelProvider]/[ChatProvider] split: model selection already
/// survives conversation switches by living outside [ChatProvider], and the
/// pending thinking/prompt values follow the same pattern — they are pushed
/// into [ChatProvider] via the `ChangeNotifierProxyProvider2` in `main.dart`
/// and consumed when a new conversation is created. The style's *model* needs
/// no pending slot here: applying a style routes it through
/// [ModelProvider.selectModel], the existing mechanism.
class StyleProvider extends ChangeNotifier with GuardedStateMixin {
  StyleProvider() {
    refresh();
  }

  final StyleService _service = StyleService.instance;

  List<Style> _styles = [];
  List<Style> get styles => List.unmodifiable(_styles);

  /// The style that seeds new conversations, if any.
  Style? get defaultStyle => _styles.where((s) => s.isDefault).firstOrNull;

  ThinkingLevel? _pendingThinkingLevel;

  /// Thinking level to use for the next new conversation; null = provider
  /// default ("Auto").
  ThinkingLevel? get pendingThinkingLevel => _pendingThinkingLevel;

  String? _pendingSystemPrompt;

  /// System prompt content (already resolved from a template) for the next
  /// new conversation; null = the user's global default applies.
  String? get pendingSystemPrompt => _pendingSystemPrompt;

  // Once the user composes something in the picker, the default style stops
  // silently re-seeding the pendings on later refreshes.
  bool _pendingTouched = false;

  void setPendingThinkingLevel(ThinkingLevel? level) {
    _pendingTouched = true;
    _pendingThinkingLevel = level;
    notifyListeners();
  }

  void setPendingSystemPrompt(String? content) {
    _pendingTouched = true;
    final trimmed = content?.trim();
    _pendingSystemPrompt = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    notifyListeners();
  }

  Future<void> refresh() async {
    await runGuarded('Failed to load styles', () async {
      _styles = await _service.listStyles();
      await _seedPendingFromDefault();
    });
  }

  /// Seed the new-conversation pendings from the default style, once, so a
  /// user who marked a style "Use for new chats" gets its thinking level and
  /// prompt without opening the picker. The style's model is persisted as the
  /// account default model when the default is set (see the picker), so
  /// [ModelProvider] already handles that side.
  Future<void> _seedPendingFromDefault() async {
    if (_pendingTouched) return;
    final def = defaultStyle;
    if (def == null) return;
    _pendingThinkingLevel = def.thinkingLevel;
    _pendingSystemPrompt = null;
    if (def.systemPromptTemplateId != null) {
      try {
        final templates = await SystemPromptService.instance.listTemplates();
        _pendingSystemPrompt = templates
            .where((t) => t.id == def.systemPromptTemplateId)
            .firstOrNull
            ?.content;
      } catch (_) {
        // Best-effort: a failed template fetch only loses the prompt seed.
      }
    }
  }

  Future<Style?> createStyle({
    required String name,
    required String modelId,
    ThinkingLevel? thinkingLevel,
    String? systemPromptTemplateId,
    bool isDefault = false,
  }) async {
    return runGuarded('Failed to save style', () async {
      final created = await _service.createStyle(
        name: name,
        modelId: modelId,
        thinkingLevel: thinkingLevel,
        systemPromptTemplateId: systemPromptTemplateId,
        isDefault: isDefault,
      );
      _styles = [
        // The backend unsets any previous default when a new one is created.
        if (created.isDefault)
          ..._styles.map((s) => s.copyWith(isDefault: false))
        else
          ..._styles,
        created,
      ];
      return created;
    }, trackLoading: false);
  }

  /// Make [styleId] the default for new conversations (or clear the flag).
  Future<Style?> setDefault(String styleId, {bool isDefault = true}) async {
    return runGuarded('Failed to update style', () async {
      final updated = await _service.updateStyle(styleId, isDefault: isDefault);
      _styles = _styles
          .map(
            (s) => s.id == updated.id
                ? updated
                : (updated.isDefault ? s.copyWith(isDefault: false) : s),
          )
          .toList();
      return updated;
    }, trackLoading: false);
  }

  Future<bool> deleteStyle(String styleId) async {
    final ok = await runGuarded('Failed to delete style', () async {
      await _service.deleteStyle(styleId);
      _styles = _styles.where((s) => s.id != styleId).toList();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }
}
