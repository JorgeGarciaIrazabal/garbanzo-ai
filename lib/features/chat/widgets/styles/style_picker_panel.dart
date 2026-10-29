import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/motion.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/utils/composer_conversation.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_cards_segment.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_customize_controls.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_editor.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_picker_helpers.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// The two sections the segmented control swaps between: one-tap saved style
/// cards, and the compose-your-own controls (model, thinking, prompt).
enum _PickerSection { styles, customize }

/// Shared picker content: a segmented [Styles | Customize] control swaps
/// between saved style cards and the composition controls. Every control
/// applies immediately (to the active conversation when there is one, and
/// always to the pending state used for the next new conversation).
class StylePickerPanel extends StatefulWidget {
  const StylePickerPanel({
    super.key,
    this.showCloseButton = false,
    this.isBottomSheet = false,
  });

  final bool showCloseButton;
  final bool isBottomSheet;

  @override
  State<StylePickerPanel> createState() => _StylePickerPanelState();
}

class _StylePickerPanelState extends State<StylePickerPanel> {
  final ScrollController _scrollController = ScrollController();

  _PickerSection? _section;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsProvider?>();
      if (settings != null) {
        context.read<SystemPromptProvider>().setLocale(
          settings.effectiveLanguageCode,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _applyStyle(Style style) async {
    final chat = context.read<ChatProvider>();
    final modelP = context.read<ModelProvider>();
    final styleP = context.read<StyleProvider>();
    final prompts = context.read<SystemPromptProvider>();
    final conversationId = composerConversation(context, listen: false)?.id;
    final pendingRevision = styleP.pendingRevision;
    final topics = context.read<TopicDiscoveryProvider?>();
    final topicEpoch = topics?.newTopicEpoch;

    if (!modelP.availableModels.any((m) => m.id == style.modelId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${style.modelId} is not installed')),
      );
      return;
    }
    final navigator = Navigator.of(context);

    String? content;
    final templateId = style.systemPromptTemplateId;
    if (templateId != null) {
      final template = await prompts.resolveTemplate(templateId);
      if (!mounted) return;
      if (template == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.styleInstructionsLoadFailed,
            ),
          ),
        );
        return;
      }
      content = template.content;
    }
    if (!mounted ||
        composerConversation(context, listen: false)?.id != conversationId ||
        styleP.pendingRevision != pendingRevision ||
        topics?.newTopicEpoch != topicEpoch) {
      return;
    }
    modelP.selectModel(style.modelId);
    styleP.setPendingThinkingLevel(style.thinkingLevel);
    styleP.setPendingSystemPrompt(content);
    await styleP.recordLastUsed(style.id);
    if (!mounted) return;

    if (conversationId != null &&
        composerConversation(context, listen: false)?.id == conversationId) {
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
    final model = context
        .read<ModelProvider>()
        .availableModels
        .where((candidate) => candidate.id == modelId)
        .firstOrNull;
    final current =
        composerConversation(context, listen: false)?.thinkingLevel ??
        context.read<StyleProvider>().pendingThinkingLevel;
    final supported = model?.supportedThinkingLevels ?? const <ThinkingLevel>[];
    final adjusted = current != null && !supported.contains(current)
        ? model?.defaultThinkingLevel ?? supported.firstOrNull
        : current;
    final chat = context.read<ChatProvider>();
    final currentModelId =
        composerConversation(context, listen: false)?.model ??
        context.read<ModelProvider>().selectedModelId;
    if (modelId != currentModelId) {
      context.read<StyleProvider>().clearSelectedStyle();
    }
    context.read<ModelProvider>().selectModel(modelId);
    if (composerConversation(context, listen: false) != null) {
      await chat.updateConversation(
        model: modelId,
        thinkingLevel: adjusted,
        setThinkingLevel: adjusted != current,
      );
    }
    if (adjusted != current && mounted) {
      context.read<StyleProvider>().setPendingThinkingLevel(adjusted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            adjusted == null
                ? 'Thinking effort reset for this model'
                : AppLocalizations.of(
                    context,
                  )!.thinkingEffortAdjusted(adjusted.label),
          ),
        ),
      );
    }
  }

  Future<void> _setThinking(ThinkingLevel? level) async {
    final chat = context.read<ChatProvider>();
    context.read<StyleProvider>().setPendingThinkingLevel(level);
    if (composerConversation(context, listen: false) != null) {
      await chat.updateConversation(
        thinkingLevel: level,
        setThinkingLevel: true,
      );
    }
  }

  Future<void> _setTemplate(String? templateId) async {
    final chat = context.read<ChatProvider>();
    final templates = context.read<SystemPromptProvider>().templates;
    final content = resolveTemplateContent(templates, templateId);
    final styleProvider = context.read<StyleProvider>();
    final currentPrompt = normalizeStylePrompt(
      composerConversation(context, listen: false)?.systemPrompt ??
          styleProvider.pendingSystemPrompt,
    );
    if (normalizeStylePrompt(content) != currentPrompt) {
      styleProvider.clearSelectedStyle();
    }
    styleProvider.setPendingSystemPrompt(content);
    if (composerConversation(context, listen: false) != null) {
      await chat.updateConversation(
        systemPrompt: content,
        clearSystemPrompt: content == null,
      );
    }
  }

  void _startEditing(Style style) => _openStyleEditor(existing: style);

  void _startCreating() => _openStyleEditor();

  Future<void> _openStyleEditor({Style? existing}) async {
    final models = context.read<ModelProvider>();
    final styles = context.read<StyleProvider>();
    final prompts = context.read<SystemPromptProvider>();
    final conv = composerConversation(context, listen: false);
    final pendingRevision = styles.pendingRevision;
    final topics = context.read<TopicDiscoveryProvider?>();
    final topicEpoch = topics?.newTopicEpoch;
    final templateId = existing?.systemPromptTemplateId;
    SystemPromptTemplate? template;
    if (templateId != null) {
      template = await prompts.resolveTemplate(templateId);
      if (!mounted ||
          composerConversation(context, listen: false)?.id != conv?.id ||
          styles.pendingRevision != pendingRevision ||
          topics?.newTopicEpoch != topicEpoch) {
        return;
      }
      if (template == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.styleInstructionsLoadFailed,
            ),
          ),
        );
        return;
      }
    }
    if (!mounted ||
        composerConversation(context, listen: false)?.id != conv?.id ||
        styles.pendingRevision != pendingRevision ||
        topics?.newTopicEpoch != topicEpoch) {
      return;
    }
    final fullscreen = widget.isBottomSheet;
    final editor = StyleEditor(
      fullscreen: fullscreen,
      existing: existing,
      modelId: existing?.modelId ?? conv?.model ?? models.selectedModelId,
      thinkingLevel: existing != null
          ? existing.thinkingLevel
          : conv != null
          ? conv.thinkingLevel
          : styles.pendingThinkingLevel,
      instructions: existing != null
          ? template?.content ?? ''
          : (conv != null ? conv.systemPrompt : styles.pendingSystemPrompt) ??
                '',
      models: models,
      styles: styles,
      prompts: prompts,
    );
    final saved = fullscreen
        ? await Navigator.of(context, rootNavigator: true).push<bool>(
            MaterialPageRoute(fullscreenDialog: true, builder: (_) => editor),
          )
        : await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => editor,
          );
    if (saved == true && mounted) {
      setState(() => _section = _PickerSection.styles);
      _scrollToTop();
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _setDefault(Style style, bool isDefault) async {
    final styleP = context.read<StyleProvider>();
    final modelP = context.read<ModelProvider>();
    await styleP.setDefault(style.id, isDefault: isDefault);
    if (isDefault) await modelP.setDefaultModel(style.modelId);
  }

  Future<void> _deleteStyle(Style style) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${style.name}"?'),
        content: Text(
          AppLocalizations.of(context)!.messageThisRemovesTheSavedStyleNot,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<StyleProvider>().deleteStyle(style.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = widget.isBottomSheet;
    final modelP = context.watch<ModelProvider>();
    final styleP = context.watch<StyleProvider>();
    final promptP = context.watch<SystemPromptProvider>();

    final conv = composerConversation(context);
    final models = modelP.availableModels;
    final templates = promptP.templates;
    final languageCode = effectiveLanguageCode(context);
    final styles = styleP.styles
        .where((s) => styleMatchesLocale(s, languageCode))
        .toList();

    final effectiveModelId = conv?.model ?? modelP.selectedModelId;
    final effectiveThinking = conv != null
        ? conv.thinkingLevel
        : styleP.pendingThinkingLevel;
    final effectivePrompt = normalizeStylePrompt(
      conv != null ? conv.systemPrompt : styleP.pendingSystemPrompt,
    );
    final selectedTemplateId = effectivePrompt == null
        ? null
        : templates
              .where((t) => normalizeStylePrompt(t.content) == effectivePrompt)
              .firstOrNull
              ?.id;
    final hasCustomPrompt =
        effectivePrompt != null && selectedTemplateId == null;

    final composeModel = models
        .where((m) => m.id == effectiveModelId)
        .firstOrNull;

    final section =
        _section ??
        (styles.isEmpty ? _PickerSection.customize : _PickerSection.styles);
    final busy = context.watch<ChatProvider>().isSending;

    final activeStyle = resolveActiveStyle(
      styleP,
      styles,
      templates,
      modelId: effectiveModelId,
      thinkingLevel: effectiveThinking,
      systemPrompt: effectivePrompt,
    );
    bool styleIsActive(Style style) => style.id == activeStyle?.id;

    return Column(
      mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: isNarrow
              ? const EdgeInsets.fromLTRB(16, 0, 8, 0)
              : const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.chatStyle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (widget.showCloseButton)
                IconButton(
                  tooltip: AppLocalizations.of(context)!.labelClose,
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
            segments: [
              ButtonSegment(
                value: _PickerSection.styles,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(AppLocalizations.of(context)!.labelStyles),
              ),
              ButtonSegment(
                value: _PickerSection.customize,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  AppLocalizations.of(context)!.labelCustomize,
                  key: const ValueKey('customize_tile'),
                ),
              ),
            ],
            selected: {section},
            showSelectedIcon: false,
            onSelectionChanged: (selected) {
              setState(() => _section = selected.first);
              _scrollToTop();
            },
          ),
        ),
        Flexible(
          fit: isNarrow ? FlexFit.tight : FlexFit.loose,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AnimatedSize(
              duration: Motion.medium,
              curve: Motion.easeOut,
              alignment: Alignment.topCenter,
              child: section == _PickerSection.styles
                  ? StylesSegment(
                      isLoading: styleP.isLoading && styleP.styles.isEmpty,
                      styles: styles,
                      styleIsActive: styleIsActive,
                      models: models,
                      templates: templates,
                      busy: busy,
                      onApply: _applyStyle,
                      onSetDefault: _setDefault,
                      onEdit: _startEditing,
                      onDelete: _deleteStyle,
                      onCreate: _startCreating,
                      showCreateTile: !isNarrow,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StyleModelList(
                          models: models,
                          selectedId: effectiveModelId,
                          enabled: !busy,
                          onSelect: _selectModel,
                        ),
                        const SizedBox(height: 16),
                        StyleThinkingControl(
                          value: effectiveThinking,
                          enabled:
                              !busy && composeModel?.supportsThinking != false,
                          supported: composeModel?.supportsThinking != false,
                          supportedLevels:
                              composeModel?.supportedThinkingLevels ?? const [],
                          onChanged: _setThinking,
                        ),
                        const SizedBox(height: 16),
                        StyleTemplatePicker(
                          templates: templates,
                          selectedId: selectedTemplateId,
                          hasCustomPrompt: hasCustomPrompt,
                          enabled: !busy,
                          onChanged: _setTemplate,
                        ),
                        if (!isNarrow) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              key: const ValueKey('save_style_button'),
                              onPressed: busy ? null : _startCreating,
                              icon: const Icon(Icons.bookmark_add_outlined),
                              label: Text(
                                AppLocalizations.of(context)!.titleSaveStyle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
        if (isNarrow)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              key: ValueKey(
                section == _PickerSection.styles
                    ? 'new_style_button'
                    : 'save_style_button',
              ),
              onPressed: busy ? null : _startCreating,
              icon: const Icon(Icons.add),
              label: Text(
                section == _PickerSection.styles
                    ? AppLocalizations.of(context)!.styleNew
                    : AppLocalizations.of(context)!.titleSaveStyle,
              ),
            ),
          ),
      ],
    );
  }
}
