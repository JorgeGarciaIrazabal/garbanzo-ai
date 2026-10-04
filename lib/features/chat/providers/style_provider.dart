import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  StyleProvider({
    StyleService? styleService,
    SystemPromptService? systemPromptService,
  }) : _service = styleService ?? StyleService.instance,
       _promptService = systemPromptService ?? SystemPromptService.instance {
    _loadFuture = refresh();
  }

  final StyleService _service;
  final SystemPromptService _promptService;
  bool _stylesLoaded = false;

  int _seedRequest = 0;
  int _pendingRevision = 0;
  bool _disposed = false;
  String? _seedError;
  bool _isSeeding = false;
  bool _seedBlocked = false;

  /// Required instructions failed to load; the landing offers an explicit retry.
  String? get seedError => _seedError;
  bool get isSeeding => _isSeeding;

  /// New-thread submission waits for required settings or an explicit prompt
  /// replacement. Thinking/model tweaks alone cannot discard required content.
  bool get pendingSeedBlocked => _seedBlocked;

  /// Guards model selection and explicit Apply against later composer changes.
  int get pendingRevision => _pendingRevision;

  void _customizePending({bool replacePrompt = false}) {
    _pendingTouched = true;
    _pendingRevision++;
    _seedRequest++;
    if (replacePrompt) {
      _seedBlocked = false;
      _seedError = null;
    } else if (_seedBlocked) {
      _seedError ??= 'Failed to load style instructions. Please try again.';
    }
    _isSeeding = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _seedRequest++;
    super.dispose();
  }

  /// Completes when the initial [refresh] finishes. Lets the new-topic window
  /// await the style list instead of seeding from an empty one.
  Future<void>? _loadFuture;

  /// Await the initial style load. Subsequent calls reuse the same future.
  Future<void> ensureLoaded() => _loadFuture ??= refresh();

  /// SharedPreferences key for the id of the last saved style the user
  /// explicitly applied. Falls back to seeding new-conversation pendings
  /// when no style is marked default (see [_seedPendingFromDefault]).
  static const _keyLastUsedStyleId = 'style_last_used_style_id';

  List<Style> _styles = [];
  List<Style> get styles => List.unmodifiable(_styles);

  /// The named style the user most recently applied.
  ///
  /// This is deliberately separate from the effective thinking level. A
  /// conversation can temporarily override effort without ceasing to be the
  /// same named model + prompt persona. The backend currently stores only the
  /// resolved settings, so startup recovers this identity from the default or
  /// last-used style and the picker verifies that its model/prompt still fit.
  String? _selectedStyleId;
  String? get selectedStyleId => _selectedStyleId;

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
    _customizePending();
    _pendingThinkingLevel = level;
    notifyListeners();
  }

  void setPendingSystemPrompt(String? content) {
    _customizePending(replacePrompt: true);
    final trimmed = content?.trim();
    _pendingSystemPrompt = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    notifyListeners();
  }

  Future<void> refresh() async {
    await runGuarded('Failed to load styles', () async {
      _styles = await _service.listStyles();
      _stylesLoaded = true;
      await _seedPendingFromDefault();
    });
  }

  /// Seed the new-conversation pendings from the default style — or, absent
  /// one, from the last saved style the user explicitly applied — once, so a
  /// returning user gets a familiar thinking level and prompt without
  /// opening the picker. An explicit default always wins over last-used: it
  /// is the stronger, deliberate signal. Either way the style's *model* is
  /// not seeded here — a default style's model is persisted as the account
  /// default model when the default is set (see the picker), so
  /// [ModelProvider] already handles that side, and last-used intentionally
  /// only follows the existing default-style seeding contract.
  Future<void> _seedPendingFromDefault() async {
    if (_pendingTouched) return;
    await _seedPending(newTopic: false);
  }

  /// Reset the composer for a new-topic window, resolving instructions before
  /// publishing identity, Medium effort and prompt together. A required lookup
  /// failure preserves the prior composed state and exposes [seedError].
  /// [isCurrent] also guards a landing that closes while lookup is in flight.
  Future<Style?> applyDefaultForNewTopic({bool Function()? isCurrent}) {
    _pendingTouched = true;
    return _seedPending(newTopic: true, isCurrent: isCurrent);
  }

  Future<Style?> _seedPending({
    required bool newTopic,
    bool Function()? isCurrent,
  }) async {
    final request = ++_seedRequest;
    final revision = _pendingRevision;
    bool current() =>
        !_disposed &&
        request == _seedRequest &&
        revision == _pendingRevision &&
        (isCurrent?.call() ?? true);
    _seedError = null;
    _isSeeding = true;
    _seedBlocked = true;
    notifyListeners();
    try {
      if (newTopic) {
        await ensureLoaded();
        if (!current()) return null;
        // Retry a failed style-list load as well as a failed prompt lookup.
        if (!_stylesLoaded) await refresh();
        if (!current()) return null;
        if (!_stylesLoaded) throw StateError('Styles have not loaded');
      }
      final seed = defaultStyle ?? await _lastUsedStyle();
      if (!current()) return null;
      final template = await _promptService.resolveTemplate(
        seed?.systemPromptTemplateId,
      );
      if (!current()) return null;
      final content = template?.content.trim();
      _selectedStyleId = seed?.id;
      _pendingThinkingLevel = newTopic
          ? ThinkingLevel.medium
          : seed?.thinkingLevel;
      _pendingSystemPrompt = content == null || content.isEmpty
          ? null
          : content;
      _pendingRevision++;
      _isSeeding = false;
      _seedBlocked = false;
      notifyListeners();
      return seed;
    } catch (e) {
      if (current()) {
        _seedError = describeFailure(
          e,
          label: 'Failed to load style instructions',
        );
        _isSeeding = false;
        notifyListeners();
      }
      return null;
    }
  }

  /// Marks [styleId] as the most recently applied saved style. Persisted in
  /// SharedPreferences (local-only, mirrors [SettingsProvider]'s prefs) so it
  /// survives app restarts.
  Future<void> recordLastUsed(String styleId) async {
    _customizePending();
    if (_selectedStyleId != styleId) {
      _selectedStyleId = styleId;
      notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastUsedStyleId, styleId);
  }

  /// Clears the named persona after its base model or prompt is customized.
  /// Thinking effort intentionally does not call this: it is a per-chat
  /// override layered on top of the selected style.
  void clearSelectedStyle() {
    _customizePending();
    _selectedStyleId = null;
    notifyListeners();
  }

  /// The last-used style, if its id is still among the user's saved styles.
  Future<Style?> _lastUsedStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyLastUsedStyleId);
    if (id == null) return null;
    return _styles.where((s) => s.id == id).firstOrNull;
  }

  Future<Style?> createStyle({
    required String name,
    required String modelId,
    ThinkingLevel? thinkingLevel,
    String? systemPromptTemplateId,
    String? systemPromptContent,
    bool isDefault = false,
  }) async {
    return runGuarded('Failed to save style', () async {
      final created = await _service.createStyle(
        name: name,
        modelId: modelId,
        thinkingLevel: thinkingLevel,
        systemPromptTemplateId: systemPromptTemplateId,
        systemPromptContent: systemPromptContent,
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

  /// Partial update, forwarding the service's three-way `set*` semantics for
  /// thinking level and template (absent = unchanged, null+flag = clear).
  Future<Style?> updateStyle(
    String styleId, {
    String? name,
    String? modelId,
    ThinkingLevel? thinkingLevel,
    bool setThinkingLevel = false,
    String? systemPromptTemplateId,
    String? systemPromptContent,
    bool setTemplateId = false,
    bool? isDefault,
  }) async {
    return runGuarded('Failed to update style', () async {
      final updated = await _service.updateStyle(
        styleId,
        name: name,
        modelId: modelId,
        thinkingLevel: thinkingLevel,
        setThinkingLevel: setThinkingLevel,
        systemPromptTemplateId: systemPromptTemplateId,
        systemPromptContent: systemPromptContent,
        setTemplateId: setTemplateId,
        isDefault: isDefault,
      );
      _styles = _styles
          .map(
            (s) => s.id == updated.id
                ? updated
                // The backend unsets any previous default.
                : (updated.isDefault ? s.copyWith(isDefault: false) : s),
          )
          .toList();
      return updated;
    }, trackLoading: false);
  }

  /// Make [styleId] the default for new conversations (or clear the flag).
  Future<Style?> setDefault(String styleId, {bool isDefault = true}) =>
      updateStyle(styleId, isDefault: isDefault);

  Future<bool> deleteStyle(String styleId) async {
    final ok = await runGuarded('Failed to delete style', () async {
      await _service.deleteStyle(styleId);
      _styles = _styles.where((s) => s.id != styleId).toList();
      if (_selectedStyleId == styleId) _selectedStyleId = null;
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }
}
