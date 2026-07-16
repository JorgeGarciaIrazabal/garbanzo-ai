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
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';

/// The style picker: replaces the plain model dropdown with a "chat style"
/// surface — saved styles (model + thinking level + system prompt bundles)
/// as one-tap cards, plus an expandable Customize section with a searchable
/// model list, thinking-level control, and prompt template picker.
///
/// [StylePickerButton] is the app-bar trigger; [showStylePicker] opens the
/// panel as an anchored popover on wide layouts and a bottom sheet on narrow
/// ones (the `mute_sheet` idiom).

/// Trims to null so "unset", empty, and whitespace prompts all compare equal.
String? _normalize(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

// ============================================================================
// Trigger button (app bar)
// ============================================================================

/// Compact app-bar pill showing the effective model (and a thinking marker),
/// opening the style picker on tap. Hidden while the model list is empty,
/// matching the old dropdown's behavior.
class StylePickerButton extends StatelessWidget {
  const StylePickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chat = context.watch<ChatProvider>();
    final modelP = context.watch<ModelProvider>();
    final styleP = context.watch<StyleProvider>();

    final models = modelP.availableModels;
    if (models.isEmpty) return const SizedBox.shrink();

    final conv = chat.currentConversation;
    // In a conversation the backend answers with the conversation's model,
    // so that is what the pill reports; outside one it shows the selection
    // the next conversation will use.
    final effectiveId = conv?.model ?? modelP.selectedModelId;
    final effectiveModel = models.where((m) => m.id == effectiveId).firstOrNull;
    final label = effectiveModel?.name ?? effectiveId ?? 'Model';
    final thinking = conv != null
        ? conv.thinkingLevel
        : styleP.pendingThinkingLevel;
    final thinkingActive = thinking != null && thinking != ThinkingLevel.off;
    final enabled = !chat.isSending;
    final fg = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Tooltip(
      message: 'Chat style',
      child: InkWell(
        key: const ValueKey('style_picker_button'),
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? () => showStylePicker(context) : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(
              alpha: enabled ? 1 : 0.5,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 14,
                color: enabled ? colorScheme.primary : fg,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (thinkingActive) ...[
                const SizedBox(width: 4),
                Icon(Icons.psychology_outlined, size: 14, color: fg),
              ],
              Icon(Icons.arrow_drop_down, size: 18, color: fg),
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
      pageBuilder: (dialogContext, _, _) => SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: kToolbarHeight + 4, right: 12),
            child: Material(
              color: Theme.of(dialogContext).colorScheme.surfaceContainerLow,
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  maxHeight:
                      MediaQuery.of(dialogContext).size.height -
                      kToolbarHeight -
                      48,
                ),
                child: withProviders(
                  const StylePickerPanel(showCloseButton: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.88,
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

/// Shared picker content: saved style cards on top, expandable Customize
/// section below. Every control applies immediately (to the active
/// conversation when there is one, and always to the pending state used for
/// the next new conversation) — there is no Apply button.
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
  String _query = '';
  bool? _customizeExpanded;

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
    super.dispose();
  }

  // ---- effective state ------------------------------------------------

  String? _templateContent(
    List<SystemPromptTemplate> templates,
    String? templateId,
  ) {
    if (templateId == null) return null;
    return _normalize(
      templates.where((t) => t.id == templateId).firstOrNull?.content,
    );
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

    final content = _templateContent(templates, style.systemPromptTemplateId);
    modelP.selectModel(style.modelId);
    styleP.setPendingThinkingLevel(style.thinkingLevel);
    styleP.setPendingSystemPrompt(content);

    final navigator = Navigator.of(context);
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
    final chat = context.read<ChatProvider>();
    context.read<ModelProvider>().selectModel(modelId);
    if (chat.currentConversation != null) {
      await chat.updateConversation(model: modelId);
    }
  }

  Future<void> _setThinking(ThinkingLevel? level) async {
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
    final chat = context.read<ChatProvider>();
    final templates = context.read<SystemPromptProvider>().templates;
    final content = _templateContent(templates, templateId);
    context.read<StyleProvider>().setPendingSystemPrompt(content);
    if (chat.currentConversation != null) {
      await chat.updateConversation(
        systemPrompt: content,
        clearSystemPrompt: content == null,
      );
    }
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
    await context.read<StyleProvider>().deleteStyle(style.id);
  }

  Future<void> _saveStyle({
    required String modelId,
    required ThinkingLevel? thinkingLevel,
    required String? templateId,
  }) async {
    final result = await showDialog<({String name, bool isDefault})>(
      context: context,
      builder: (_) => const _SaveStyleDialog(),
    );
    if (result == null || !mounted) return;
    final styleP = context.read<StyleProvider>();
    final modelP = context.read<ModelProvider>();
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
    final effectiveModel = models
        .where((m) => m.id == effectiveModelId)
        .firstOrNull;
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

    // With no saved styles yet, composing is the only thing to do here.
    final customizeExpanded = _customizeExpanded ?? styles.isEmpty;
    final busy = chat.isSending;

    bool styleIsActive(Style s) =>
        s.modelId == effectiveModelId &&
        s.thinkingLevel == effectiveThinking &&
        _templateContent(templates, s.systemPromptTemplateId) ==
            effectivePrompt;

    final filteredModels = _query.isEmpty
        ? models
        : models
              .where(
                (m) =>
                    m.id.toLowerCase().contains(_query) ||
                    m.name.toLowerCase().contains(_query) ||
                    (m.description?.toLowerCase().contains(_query) ?? false),
              )
              .toList();

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
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (styleP.isLoading && styles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (styles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text(
                      'No saved styles yet. Customize below, then save the '
                      'combination to switch in one tap.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
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
                            .where((t) => t.id == s.systemPromptTemplateId)
                            .firstOrNull
                            ?.name,
                        enabled: !busy,
                        onTap: () => _applyStyle(s),
                        onSetDefault: (v) => _setDefault(s, v),
                        onDelete: () => _deleteStyle(s),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                _CustomizeHeader(
                  key: const ValueKey('customize_tile'),
                  expanded: customizeExpanded,
                  summary: _compositionSummary(
                    effectiveModel?.name ?? effectiveModelId,
                    effectiveThinking,
                    hasCustomPrompt
                        ? 'Custom prompt'
                        : templates
                              .where((t) => t.id == selectedTemplateId)
                              .firstOrNull
                              ?.name,
                  ),
                  onTap: () =>
                      setState(() => _customizeExpanded = !customizeExpanded),
                ),
                AnimatedSize(
                  duration: Motion.medium,
                  curve: Motion.easeOut,
                  alignment: Alignment.topCenter,
                  child: !customizeExpanded
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            TextField(
                              key: const ValueKey('style_search_field'),
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search models',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                isDense: true,
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: _searchController.clear,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _ModelList(
                              models: filteredModels,
                              selectedId: effectiveModelId,
                              enabled: !busy,
                              onSelect: _selectModel,
                            ),
                            const SizedBox(height: 16),
                            _ThinkingControl(
                              value: effectiveThinking,
                              enabled:
                                  !busy &&
                                  effectiveModel?.supportsThinking != false,
                              supported:
                                  effectiveModel?.supportsThinking != false,
                              onChanged: _setThinking,
                            ),
                            const SizedBox(height: 16),
                            _TemplatePicker(
                              templates: templates,
                              selectedId: selectedTemplateId,
                              hasCustomPrompt: hasCustomPrompt,
                              enabled: !busy,
                              onChanged: _setTemplate,
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                key: const ValueKey('save_style_button'),
                                onPressed: (busy || effectiveModelId == null)
                                    ? null
                                    : () => _saveStyle(
                                        modelId: effectiveModelId,
                                        thinkingLevel: effectiveThinking,
                                        templateId: selectedTemplateId,
                                      ),
                                icon: const Icon(Icons.bookmark_add_outlined),
                                label: const Text('Save style'),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _compositionSummary(
    String? modelLabel,
    ThinkingLevel? thinking,
    String? promptLabel,
  ) {
    return [
      modelLabel ?? 'No model',
      'Thinking ${thinking?.label.toLowerCase() ?? 'auto'}',
      promptLabel ?? 'No template',
    ].join(' · ');
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

class _CustomizeHeader extends StatelessWidget {
  const _CustomizeHeader({
    super.key,
    required this.expanded,
    required this.summary,
    required this.onTap,
  });

  final bool expanded;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.tune, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customize', style: theme.textTheme.titleSmall),
                  Text(
                    summary,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: Motion.fast,
              child: Icon(
                Icons.expand_more,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelList extends StatelessWidget {
  const _ModelList({
    required this.models,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
  });

  final List<ModelInfo> models;
  final String? selectedId;
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
                'No models match your search.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 236),
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
                          _CapabilityBadges(model: model),
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

/// Tiny icon badges for provider-reported capabilities. Flags are tri-state
/// (null = unknown), so a badge only shows when the capability is confirmed;
/// any new flags the models endpoint grows slot in as another `(flag, icon,
/// label)` entry here.
class _CapabilityBadges extends StatelessWidget {
  const _CapabilityBadges({required this.model});

  final ModelInfo model;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badges = <(bool?, IconData, String)>[
      (model.supportsVision, Icons.visibility_outlined, 'Vision'),
      (model.supportsTools, Icons.build_outlined, 'Tools'),
      (model.supportsThinking, Icons.psychology_outlined, 'Thinking'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (flag, icon, label) in badges)
          if (flag == true)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: label,
                child: Icon(
                  icon,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
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
                visualDensity: VisualDensity.compact,
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
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('template_dropdown'),
              value: value,
              isExpanded: true,
              isDense: true,
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
  const _SaveStyleDialog();

  @override
  State<_SaveStyleDialog> createState() => _SaveStyleDialogState();
}

class _SaveStyleDialogState extends State<_SaveStyleDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isDefault = false;

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
      title: const Text('Save style'),
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
