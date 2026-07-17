import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/motion.dart';
import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/friends/widgets/share_with_friend_dialog.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';

/// The style picker: replaces the plain model dropdown with a "chat style"
/// surface — saved styles (model + thinking level + system prompt bundles)
/// as one-tap cards, plus a Customize section with a searchable model list,
/// thinking-level control, and prompt template picker. A segmented control
/// swaps between the two sections so the surface stays content-sized on
/// every form factor.
///
/// [StylePickerButton] is the app-bar trigger; [showStylePicker] opens the
/// panel as an anchored popover on wide layouts and a bottom sheet on narrow
/// ones (the `mute_sheet` idiom). The popover scales its width and text with
/// the window so it stays proportional on large desktop monitors.

/// The capability vocabulary, shared by the model rows' badges and the
/// capability filter so a filter chip reads as exactly the same thing the
/// rows show. Any new flag the models endpoint grows slots in here once and
/// appears in both places.
enum _Capability {
  vision(Icons.visibility_outlined, 'Vision'),
  tools(Icons.build_outlined, 'Tools'),
  thinking(Icons.psychology_outlined, 'Thinking');

  const _Capability(this.icon, this.label);

  final IconData icon;
  final String label;

  /// Tri-state: true/false as reported by the provider, null when it reported
  /// nothing (capability lookup failed, or a provider that doesn't advertise
  /// them at all).
  bool? of(ModelInfo model) => switch (this) {
    _Capability.vision => model.supportsVision,
    _Capability.tools => model.supportsTools,
    _Capability.thinking => model.supportsThinking,
  };

  /// Whether [model] survives a filter on this capability. Only a confirmed
  /// `false` is excluded: an unknown flag means we never learned the answer,
  /// and hiding a model over a failed lookup would silently strip it from the
  /// only list the user can pick from. Unknowns are kept and marked (see
  /// [_CapabilityBadges]) so the row reads as "maybe" rather than a false
  /// positive.
  bool allows(ModelInfo model) => of(model) != false;
}

/// Trims to null so "unset", empty, and whitespace prompts all compare equal.
String? _normalize(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Resolves a system-prompt-template id to its (normalized) content, or null
/// for "no template" / a template that no longer exists. Shared by the panel
/// (effective-prompt resolution, template dropdown fallback) and the app-bar
/// pill (active-style matching), so a conversation prompt that happens to
/// equal a template's content is recognized consistently everywhere.
String? _resolveTemplateContent(
  List<SystemPromptTemplate> templates,
  String? templateId,
) {
  if (templateId == null) return null;
  return _normalize(
    templates.where((t) => t.id == templateId).firstOrNull?.content,
  );
}

/// A saved style is "active" for the given effective settings when all three
/// of its settings (model, thinking level, resolved prompt) match. There is
/// no backend notion of "the active style" — a conversation only stores the
/// resolved model/thinking/prompt, not which style (if any) produced them —
/// so this is derived on the fly. Reused by the app-bar pill (to show the
/// style name instead of the bare model) and the picker's saved-style cards
/// (to highlight the currently-applied one).
bool _styleMatches(
  Style style,
  List<SystemPromptTemplate> templates, {
  required String? modelId,
  required ThinkingLevel? thinkingLevel,
  required String? systemPrompt,
}) {
  return style.modelId == modelId &&
      style.thinkingLevel == thinkingLevel &&
      _resolveTemplateContent(templates, style.systemPromptTemplateId) ==
          systemPrompt;
}

// ============================================================================
// Trigger button (app bar)
// ============================================================================

/// Compact app-bar pill showing the active style name — or, when the
/// effective settings match no saved style, the effective model (and a
/// thinking marker) exactly as before. Opens the style picker on tap. Hidden
/// while the model list is empty, matching the old dropdown's behavior.
class StylePickerButton extends StatelessWidget {
  const StylePickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chat = context.watch<ChatProvider>();
    final modelP = context.watch<ModelProvider>();
    final styleP = context.watch<StyleProvider>();
    final promptP = context.watch<SystemPromptProvider>();

    final models = modelP.availableModels;
    if (models.isEmpty) return const SizedBox.shrink();

    final conv = chat.currentConversation;
    // In a conversation the backend answers with the conversation's model,
    // so that is what the pill reports; outside one it shows the selection
    // the next conversation will use.
    final effectiveId = conv?.model ?? modelP.selectedModelId;
    final effectiveModel = models.where((m) => m.id == effectiveId).firstOrNull;
    final thinking = conv != null
        ? conv.thinkingLevel
        : styleP.pendingThinkingLevel;
    final prompt = _normalize(
      conv != null ? conv.systemPrompt : styleP.pendingSystemPrompt,
    );
    // No backend column tracks "the active style" — it's derived by matching
    // the effective model/thinking/prompt against saved styles, same logic
    // the panel uses to highlight a style's card.
    final activeStyle = styleP.styles
        .where(
          (s) => _styleMatches(
            s,
            promptP.templates,
            modelId: effectiveId,
            thinkingLevel: thinking,
            systemPrompt: prompt,
          ),
        )
        .firstOrNull;
    final label =
        activeStyle?.name ?? effectiveModel?.name ?? effectiveId ?? 'Model';
    final monogram = activeStyle == null
        ? null
        : (activeStyle.name.isEmpty
              ? '?'
              : String.fromCharCode(
                  activeStyle.name.runes.first,
                ).toUpperCase());
    final thinkingActive = thinking != null && thinking != ThinkingLevel.off;
    final enabled = !chat.isSending;
    final fg = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    // Wide layouts have room for a roomier pill; narrow stays compact so the
    // app bar keeps space for the title.
    final wide = context.isWide;

    return Tooltip(
      message: 'Chat style',
      child: InkWell(
        key: const ValueKey('style_picker_button'),
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? () => showStylePicker(context) : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 12 : 10,
            vertical: wide ? 8 : 6,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(
              alpha: enabled ? 1 : 0.5,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A matched style gets the same monogram treatment as its card
              // in the picker, so the pill reads as "this style" rather than
              // just another label; otherwise the plain sparkle icon.
              if (monogram != null)
                CircleAvatar(
                  radius: wide ? 9 : 8,
                  backgroundColor: enabled
                      ? colorScheme.primary
                      : colorScheme.primary.withValues(alpha: 0.5),
                  child: Text(
                    monogram,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: wide ? 10 : 9,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.auto_awesome,
                  size: wide ? 16 : 14,
                  color: enabled ? colorScheme.primary : fg,
                ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 220 : 160),
                child: Text(
                  label,
                  style:
                      (wide
                              ? theme.textTheme.labelLarge
                              : theme.textTheme.labelMedium)
                          ?.copyWith(fontWeight: FontWeight.w600, color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (thinkingActive) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.psychology_outlined,
                  size: wide ? 16 : 14,
                  color: fg,
                ),
              ],
              Icon(Icons.arrow_drop_down, size: wide ? 20 : 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Opening (popover on desktop, bottom sheet on mobile)
// ============================================================================

/// Opens the style picker. The panel lives on its own route, so the chat
/// page's providers are re-exposed to it (same gotcha as
/// `SystemPromptEditorDialog.show`).
Future<void> showStylePicker(BuildContext context) {
  final chat = context.read<ChatProvider>();
  final models = context.read<ModelProvider>();
  final styles = context.read<StyleProvider>();
  final prompts = context.read<SystemPromptProvider>();

  Widget withProviders(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider.value(value: models),
      ChangeNotifierProvider.value(value: styles),
      ChangeNotifierProvider.value(value: prompts),
    ],
    child: child,
  );

  if (context.isWide) {
    // Anchored popover: slides down from where the trigger pill sits, so it
    // reads as an expansion of the pill rather than a modal interruption.
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      transitionDuration: Motion.medium,
      transitionBuilder: (context, animation, _, child) {
        final curve = CurvedAnimation(parent: animation, curve: Motion.easeOut);
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.02),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, _, _) {
        final screen = MediaQuery.of(dialogContext).size;
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(
                top: kToolbarHeight + 4,
                right: 12,
              ),
              child: Material(
                color: Theme.of(dialogContext).colorScheme.surfaceContainerLow,
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // Scale with the window: a fixed 400dp reads tiny on a
                    // large desktop monitor, but never exceed 560 so rows
                    // stay scannable.
                    maxWidth: (screen.width * 0.38).clamp(440.0, 560.0),
                    maxHeight: screen.height - kToolbarHeight - 48,
                  ),
                  child: MediaQuery(
                    // Pointer-driven desktops are fine with denser type, but
                    // the panel still sizes up a notch so it does not read as
                    // a phone UI lost on a big screen.
                    data: MediaQuery.of(
                      dialogContext,
                    ).copyWith(textScaler: const TextScaler.linear(1.12)),
                    child: withProviders(
                      const StylePickerPanel(showCloseButton: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      // Content-sized up to this cap; the segmented layout keeps the sheet
      // from becoming a fullscreen takeover.
      maxHeight: MediaQuery.of(context).size.height * 0.8,
    ),
    builder: (sheetContext) => Padding(
      // Keep the model search field above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: withProviders(const StylePickerPanel()),
    ),
  );
}

// ============================================================================
// Panel
// ============================================================================

/// The two sections the segmented control swaps between: one-tap saved style
/// cards, and the compose-your-own controls (model, thinking, prompt).
enum _PickerSection { styles, customize }

/// Shared picker content: a segmented [Styles | Customize] control swaps
/// between saved style cards and the composition controls. Every control
/// applies immediately (to the active conversation when there is one, and
/// always to the pending state used for the next new conversation) — there
/// is no Apply button.
///
/// The segmented layout replaces an inline expanding Customize section:
/// expanding inline let the bottom sheet balloon to near-fullscreen on
/// phones, while swapping sections keeps the surface content-sized on every
/// form factor.
class StylePickerPanel extends StatefulWidget {
  const StylePickerPanel({super.key, this.showCloseButton = false});

  /// Popovers get an explicit close affordance; the bottom sheet has its
  /// drag handle instead.
  final bool showCloseButton;

  @override
  State<StylePickerPanel> createState() => _StylePickerPanelState();
}

class _StylePickerPanelState extends State<StylePickerPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  /// Capabilities the model list is filtered on. Composes with [_query]
  /// (both must pass) rather than replacing it; empty means no filtering.
  final Set<_Capability> _filters = {};

  /// The visible section. Null derives it: Styles when saved styles exist,
  /// Customize otherwise — so saving a first style flips the view to it.
  _PickerSection? _section;

  /// When set, the customize section edits this saved style with the local
  /// `_edit*` composition below instead of the live conversation/pendings —
  /// so re-shaping a style never touches the current chat.
  Style? _editing;
  String? _editModelId;
  ThinkingLevel? _editThinking;
  String? _editTemplateId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---- apply actions ---------------------------------------------------

  Future<void> _applyStyle(Style style) async {
    final chat = context.read<ChatProvider>();
    final modelP = context.read<ModelProvider>();
    final styleP = context.read<StyleProvider>();
    final templates = context.read<SystemPromptProvider>().templates;

    if (!modelP.availableModels.any((m) => m.id == style.modelId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${style.modelId} is not installed')),
      );
      return;
    }
    // Captured before any `await` below so popping afterward never touches
    // a possibly-stale BuildContext.
    final navigator = Navigator.of(context);

    final content = _resolveTemplateContent(
      templates,
      style.systemPromptTemplateId,
    );
    modelP.selectModel(style.modelId);
    styleP.setPendingThinkingLevel(style.thinkingLevel);
    styleP.setPendingSystemPrompt(content);
    // Persisted locally so this style also seeds new-conversation pendings
    // on the next app start when no style is marked default.
    await styleP.recordLastUsed(style.id);

    if (chat.currentConversation != null) {
      await chat.updateConversation(
        model: style.modelId,
        thinkingLevel: style.thinkingLevel,
        setThinkingLevel: true,
        systemPrompt: content,
        clearSystemPrompt: content == null,
      );
    }
    if (mounted) navigator.pop();
  }

  Future<void> _selectModel(String modelId) async {
    if (_editing != null) {
      setState(() => _editModelId = modelId);
      return;
    }
    final chat = context.read<ChatProvider>();
    context.read<ModelProvider>().selectModel(modelId);
    if (chat.currentConversation != null) {
      await chat.updateConversation(model: modelId);
    }
  }

  Future<void> _setThinking(ThinkingLevel? level) async {
    if (_editing != null) {
      setState(() => _editThinking = level);
      return;
    }
    final chat = context.read<ChatProvider>();
    context.read<StyleProvider>().setPendingThinkingLevel(level);
    if (chat.currentConversation != null) {
      await chat.updateConversation(
        thinkingLevel: level,
        setThinkingLevel: true,
      );
    }
  }

  Future<void> _setTemplate(String? templateId) async {
    if (_editing != null) {
      setState(() => _editTemplateId = templateId);
      return;
    }
    final chat = context.read<ChatProvider>();
    final templates = context.read<SystemPromptProvider>().templates;
    final content = _resolveTemplateContent(templates, templateId);
    context.read<StyleProvider>().setPendingSystemPrompt(content);
    if (chat.currentConversation != null) {
      await chat.updateConversation(
        systemPrompt: content,
        clearSystemPrompt: content == null,
      );
    }
  }

  void _startEditing(Style style) {
    setState(() {
      _editing = style;
      _editModelId = style.modelId;
      _editThinking = style.thinkingLevel;
      _editTemplateId = style.systemPromptTemplateId;
      _section = _PickerSection.customize;
    });
    _scrollToTop();
  }

  void _cancelEditing() => setState(() => _editing = null);

  /// Section swaps change the content under the same scroll view, so reset
  /// the position or the new section can start scrolled halfway down.
  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _setDefault(Style style, bool isDefault) async {
    final styleP = context.read<StyleProvider>();
    final modelP = context.read<ModelProvider>();
    await styleP.setDefault(style.id, isDefault: isDefault);
    // A default style seeds new conversations; its model rides the existing
    // account default-model mechanism so ModelProvider restores it at login.
    if (isDefault) await modelP.setDefaultModel(style.modelId);
  }

  Future<void> _deleteStyle(Style style) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${style.name}"?'),
        content: const Text('This removes the saved style, not any chats.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await context.read<StyleProvider>().deleteStyle(style.id);
    if (ok && _editing?.id == style.id) _cancelEditing();
  }

  Future<void> _saveStyle({
    required String modelId,
    required ThinkingLevel? thinkingLevel,
    required String? templateId,
  }) async {
    final editing = _editing;
    final result = await showDialog<({String name, bool isDefault})>(
      context: context,
      builder: (_) => _SaveStyleDialog(existing: editing),
    );
    if (result == null || !mounted) return;
    final styleP = context.read<StyleProvider>();
    final modelP = context.read<ModelProvider>();
    if (editing != null) {
      final updated = await styleP.updateStyle(
        editing.id,
        name: result.name,
        modelId: modelId,
        thinkingLevel: thinkingLevel,
        setThinkingLevel: true,
        systemPromptTemplateId: templateId,
        setTemplateId: true,
        isDefault: result.isDefault,
      );
      if (updated == null) return;
      if (updated.isDefault) await modelP.setDefaultModel(updated.modelId);
      if (mounted) _cancelEditing();
      return;
    }
    final created = await styleP.createStyle(
      name: result.name,
      modelId: modelId,
      thinkingLevel: thinkingLevel,
      systemPromptTemplateId: templateId,
      isDefault: result.isDefault,
    );
    if (created != null && created.isDefault) {
      await modelP.setDefaultModel(created.modelId);
    }
  }

  // ---- build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chat = context.watch<ChatProvider>();
    final modelP = context.watch<ModelProvider>();
    final styleP = context.watch<StyleProvider>();
    final promptP = context.watch<SystemPromptProvider>();

    final conv = chat.currentConversation;
    final models = modelP.availableModels;
    final templates = promptP.templates;
    final styles = styleP.styles;

    final effectiveModelId = conv?.model ?? modelP.selectedModelId;
    final effectiveThinking = conv != null
        ? conv.thinkingLevel
        : styleP.pendingThinkingLevel;
    final effectivePrompt = _normalize(
      conv != null ? conv.systemPrompt : styleP.pendingSystemPrompt,
    );
    // Resolve the prompt content back to a template for the dropdown. A
    // conversation prompt that matches no template shows as a custom prompt.
    final selectedTemplateId = effectivePrompt == null
        ? null
        : templates
              .where((t) => _normalize(t.content) == effectivePrompt)
              .firstOrNull
              ?.id;
    final hasCustomPrompt =
        effectivePrompt != null && selectedTemplateId == null;

    // What the customize controls show: the live conversation/pendings, or —
    // while editing a saved style — the local edit composition.
    final editing = _editing;
    final composeModelId = editing != null ? _editModelId : effectiveModelId;
    final composeModel = models
        .where((m) => m.id == composeModelId)
        .firstOrNull;
    final composeThinking = editing != null ? _editThinking : effectiveThinking;
    final composeTemplateId = editing != null
        ? _editTemplateId
        : selectedTemplateId;
    final composeHasCustomPrompt = editing == null && hasCustomPrompt;

    // With no saved styles yet, composing is the only thing to do here.
    final section =
        _section ??
        (styles.isEmpty ? _PickerSection.customize : _PickerSection.styles);
    final busy = chat.isSending;

    bool styleIsActive(Style s) => _styleMatches(
      s,
      templates,
      modelId: effectiveModelId,
      thinkingLevel: effectiveThinking,
      systemPrompt: effectivePrompt,
    );

    bool matchesQuery(ModelInfo m) =>
        _query.isEmpty ||
        m.id.toLowerCase().contains(_query) ||
        m.name.toLowerCase().contains(_query) ||
        (m.description?.toLowerCase().contains(_query) ?? false);

    // Text search and capability filters compose: a model must pass both, and
    // several filters are an AND (pick a model that can do all of these).
    final filteredModels = models
        .where((m) => matchesQuery(m) && _filters.every((c) => c.allows(m)))
        .toList();

    // The empty state has to name whichever of the two narrowed the list to
    // nothing, or a filter-emptied list reads as a broken search.
    final emptyMessage = switch ((_query.isNotEmpty, _filters.isNotEmpty)) {
      (true, true) =>
        'No models match your search and the selected '
            'capabilities.',
      (true, false) => 'No models match your search.',
      (false, true) => 'No models have the selected capabilities.',
      (false, false) => 'No models available.',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Chat style', style: theme.textTheme.titleMedium),
              ),
              if (widget.showCloseButton)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                )
              else
                const SizedBox(height: 40),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SegmentedButton<_PickerSection>(
            segments: const [
              ButtonSegment(
                value: _PickerSection.styles,
                icon: Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text('Styles'),
              ),
              ButtonSegment(
                value: _PickerSection.customize,
                icon: Icon(Icons.tune, size: 18),
                label: Text('Customize', key: ValueKey('customize_tile')),
              ),
            ],
            selected: {section},
            showSelectedIcon: false,
            // Switching views is a pure view operation, so unlike the
            // composition controls it stays usable while a message streams.
            onSelectionChanged: (selected) {
              setState(() => _section = selected.first);
              _scrollToTop();
            },
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AnimatedSize(
              duration: Motion.medium,
              curve: Motion.easeOut,
              alignment: Alignment.topCenter,
              child: section == _PickerSection.styles
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (styleP.isLoading && styles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        else if (styles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No saved styles yet. Compose a model, '
                                  'thinking level, and prompt in Customize, '
                                  'then save the combination to switch in '
                                  'one tap.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(
                                      () => _section = _PickerSection.customize,
                                    );
                                    _scrollToTop();
                                  },
                                  child: const Text('Compose a style'),
                                ),
                              ],
                            ),
                          )
                        else
                          ...styles.map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _StyleCard(
                                key: ValueKey('style_card_${s.id}'),
                                style: s,
                                active: styleIsActive(s),
                                modelName: models
                                    .where((m) => m.id == s.modelId)
                                    .firstOrNull
                                    ?.name,
                                templateName: templates
                                    .where(
                                      (t) => t.id == s.systemPromptTemplateId,
                                    )
                                    .firstOrNull
                                    ?.name,
                                enabled: !busy,
                                onTap: () => _applyStyle(s),
                                onSetDefault: (v) => _setDefault(s, v),
                                onEdit: () => _startEditing(s),
                                onDelete: () => _deleteStyle(s),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (editing != null) ...[
                          Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Editing "${editing.name}"',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('cancel_edit_style'),
                                tooltip: 'Stop editing',
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: _cancelEditing,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        TextField(
                          key: const ValueKey('style_search_field'),
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search models',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: context.isNarrow,
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: _searchController.clear,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Filtering is a pure view operation, so unlike
                        // the controls below it stays usable while a
                        // message is streaming.
                        _CapabilityFilter(
                          selected: _filters,
                          onToggle: (c) => setState(
                            () => _filters.contains(c)
                                ? _filters.remove(c)
                                : _filters.add(c),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ModelList(
                          models: filteredModels,
                          selectedId: composeModelId,
                          filters: _filters,
                          emptyMessage: emptyMessage,
                          enabled: !busy,
                          onSelect: _selectModel,
                        ),
                        const SizedBox(height: 16),
                        _ThinkingControl(
                          value: composeThinking,
                          enabled:
                              !busy && composeModel?.supportsThinking != false,
                          supported: composeModel?.supportsThinking != false,
                          onChanged: _setThinking,
                        ),
                        const SizedBox(height: 16),
                        _TemplatePicker(
                          templates: templates,
                          selectedId: composeTemplateId,
                          hasCustomPrompt: composeHasCustomPrompt,
                          enabled: !busy,
                          onChanged: _setTemplate,
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            key: const ValueKey('save_style_button'),
                            onPressed: (busy || composeModelId == null)
                                ? null
                                : () => _saveStyle(
                                    modelId: composeModelId,
                                    thinkingLevel: composeThinking,
                                    templateId: composeTemplateId,
                                  ),
                            icon: Icon(
                              editing != null
                                  ? Icons.save_outlined
                                  : Icons.bookmark_add_outlined,
                            ),
                            label: Text(
                              editing != null ? 'Save changes' : 'Save style',
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Saved style card
// ============================================================================

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    super.key,
    required this.style,
    required this.active,
    required this.modelName,
    required this.templateName,
    required this.enabled,
    required this.onTap,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final Style style;
  final bool active;

  /// Display name of the style's model, or null when it is not installed.
  final String? modelName;
  final String? templateName;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final available = modelName != null;
    final monogram = style.name.isEmpty
        ? '?'
        : String.fromCharCode(style.name.runes.first).toUpperCase();
    final composition = [
      modelName ?? style.modelId,
      'Thinking ${style.thinkingLevel?.label.toLowerCase() ?? 'auto'}',
      ?templateName,
    ].join(' · ');

    return AnimatedContainer(
      duration: Motion.fast,
      decoration: BoxDecoration(
        color: active
            ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: active
                      ? colorScheme.primary
                      : colorScheme.primaryContainer,
                  child: Text(
                    monogram,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: active
                          ? colorScheme.onPrimary
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              style.name,
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (style.isDefault) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Used for new chats',
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        composition,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!available)
                  Tooltip(
                    message: '${style.modelId} is not installed',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: colorScheme.error,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Style options',
                  iconSize: 18,
                  onSelected: (action) {
                    switch (action) {
                      case 'default':
                        onSetDefault(!style.isDefault);
                      case 'edit':
                        onEdit();
                      case 'share':
                        showShareWithFriendDialog(
                          context,
                          kind: 'style',
                          itemId: style.id,
                          itemName: style.name,
                        );
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'default',
                      child: Text(
                        style.isDefault
                            ? 'Stop using for new chats'
                            : 'Use for new chats',
                      ),
                    ),
                    const PopupMenuItem(value: 'edit', child: Text('Edit…')),
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Share with a friend…'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Customize section pieces
// ============================================================================

class _ModelList extends StatelessWidget {
  const _ModelList({
    required this.models,
    required this.selectedId,
    required this.filters,
    required this.emptyMessage,
    required this.enabled,
    required this.onSelect,
  });

  final List<ModelInfo> models;
  final String? selectedId;

  /// Capabilities currently filtered on; forwarded to the badges so rows kept
  /// on an unknown flag say so.
  final Set<_Capability> filters;

  /// Names whatever emptied the list (search text, filters, or both).
  final String emptyMessage;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: models.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                emptyMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ConstrainedBox(
              // Wide surfaces have room to show more rows before scrolling.
              constraints: BoxConstraints(
                maxHeight: context.isWide ? 340 : 236,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: models.length,
                itemBuilder: (context, index) {
                  final model = models[index];
                  final selected = model.id == selectedId;
                  return InkWell(
                    key: ValueKey('model_row_${model.id}'),
                    onTap: enabled ? () => onSelect(model.id) : null,
                    child: Container(
                      color: selected
                          ? colorScheme.secondaryContainer.withValues(
                              alpha: 0.45,
                            )
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  model.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (model.description != null)
                                  Text(
                                    model.description!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CapabilityBadges(model: model, filters: filters),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Tiny icon badges for provider-reported capabilities, drawn from the shared
/// [_Capability] vocabulary. Flags are tri-state (null = unknown), so a solid
/// badge only shows when the capability is confirmed.
///
/// An unknown flag additionally gets a faded badge while that capability is
/// being filtered on: such a model is deliberately kept in the list (see
/// [_Capability.allows]), and without the marker the row would look like the
/// filter had let through a model that plainly lacks the capability.
class _CapabilityBadges extends StatelessWidget {
  const _CapabilityBadges({required this.model, this.filters = const {}});

  final ModelInfo model;
  final Set<_Capability> filters;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final capability in _Capability.values)
          if (capability.of(model) == true)
            _Badge(
              capability: capability,
              color: colorScheme.onSurfaceVariant,
              tooltip: capability.label,
            )
          else if (capability.of(model) == null && filters.contains(capability))
            _Badge(
              capability: capability,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
              tooltip: '${capability.label} unknown for this model',
            ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.capability,
    required this.color,
    required this.tooltip,
  });

  final _Capability capability;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Icon(capability.icon, size: 16, color: color),
      ),
    );
  }
}

/// Capability filter for the model list: one chip per badge, same icon and
/// label, so the control reads as "the things you see on the rows".
class _CapabilityFilter extends StatelessWidget {
  const _CapabilityFilter({required this.selected, required this.onToggle});

  final Set<_Capability> selected;
  final ValueChanged<_Capability> onToggle;

  @override
  Widget build(BuildContext context) {
    // Wrapping chips rather than a SegmentedButton, which clips at 360dp —
    // same reason as the thinking control below. Compact density only on
    // narrow touch layouts; pointer-driven wide layouts get full-size chips.
    final density = context.isWide
        ? VisualDensity.standard
        : VisualDensity.compact;
    return Wrap(
      key: const ValueKey('capability_filter'),
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final capability in _Capability.values)
          FilterChip(
            key: ValueKey('capability_filter_${capability.name}'),
            // The icon is the vocabulary link to the row badges, so it stays
            // put instead of being swapped out for a selected checkmark.
            showCheckmark: false,
            avatar: Icon(capability.icon, size: 16),
            label: Text(capability.label),
            selected: selected.contains(capability),
            visualDensity: density,
            onSelected: (_) => onToggle(capability),
          ),
      ],
    );
  }
}

class _ThinkingControl extends StatelessWidget {
  const _ThinkingControl({
    required this.value,
    required this.enabled,
    required this.supported,
    required this.onChanged,
  });

  final ThinkingLevel? value;
  final bool enabled;
  final bool supported;
  final ValueChanged<ThinkingLevel?> onChanged;

  static const _auto = 'auto';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text('Thinking', style: theme.textTheme.titleSmall),
              if (!supported) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Not supported by this model',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Choice chips wrap on narrow screens instead of clipping the way a
        // five-segment SegmentedButton does at 360dp.
        Wrap(
          key: const ValueKey('thinking_segment'),
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final (name, label) in [
              (_auto, 'Auto'),
              for (final level in ThinkingLevel.values)
                (level.name, level.label),
            ])
              ChoiceChip(
                label: Text(label),
                selected: (value?.name ?? _auto) == name,
                visualDensity: context.isWide
                    ? VisualDensity.standard
                    : VisualDensity.compact,
                onSelected: enabled
                    ? (_) => onChanged(
                        name == _auto
                            ? null
                            : ThinkingLevel.values.byName(name),
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({
    required this.templates,
    required this.selectedId,
    required this.hasCustomPrompt,
    required this.enabled,
    required this.onChanged,
  });

  final List<SystemPromptTemplate> templates;
  final String? selectedId;

  /// The active prompt matches no template (set via the prompt editor).
  final bool hasCustomPrompt;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  /// Sentinel for "no template" so every dropdown item has a distinct,
  /// non-null value (a null-valued item plus a null `value` is how the old
  /// template dropdown ended up asserting — see 8131cdf).
  static const _none = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // A stale id (deleted template) falls back to the sentinel instead of
    // tripping DropdownButton's exactly-one-match assert.
    final value = templates.any((t) => t.id == selectedId)
        ? selectedId!
        : _none;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('Prompt', style: theme.textTheme.titleSmall),
        ),
        // A plain DropdownButton (not the FormField flavor) so the shown
        // value is always the one derived from live state above — a template
        // deleted mid-session can never linger in FormField-internal state.
        InputDecorator(
          decoration: InputDecoration(
            isDense: context.isNarrow,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: context.isWide ? 8 : 4,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('template_dropdown'),
              value: value,
              isExpanded: true,
              isDense: context.isNarrow,
              items: [
                const DropdownMenuItem(
                  value: _none,
                  child: Text('No template'),
                ),
                for (final t in templates)
                  DropdownMenuItem(
                    value: t.id,
                    child: Row(
                      children: [
                        Icon(
                          t.isBuiltin
                              ? Icons.auto_awesome_outlined
                              : Icons.edit_note,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(t.name, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: enabled
                  ? (v) => onChanged(v == _none ? null : v)
                  : null,
            ),
          ),
        ),
        if (hasCustomPrompt)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              'This conversation has a custom prompt. Picking a template '
              'replaces it.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// Save style dialog
// ============================================================================

class _SaveStyleDialog extends StatefulWidget {
  const _SaveStyleDialog({this.existing});

  /// When set, the dialog edits this style: name/default pre-filled.
  final Style? existing;

  @override
  State<_SaveStyleDialog> createState() => _SaveStyleDialogState();
}

class _SaveStyleDialogState extends State<_SaveStyleDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _isDefault = existing.isDefault;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, isDefault: _isDefault));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Save style' : 'Edit style'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('style_name_field'),
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Deep work, Quick answers…',
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Use for new chats'),
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save_style_confirm'),
          onPressed: _nameController.text.trim().isEmpty ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
