import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/style_instructions_assistant.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_customize_controls.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Style editor (fullscreen on phones, dialog on desktop).
class StyleEditor extends StatefulWidget {
  const StyleEditor({
    super.key,
    required this.fullscreen,
    this.existing,
    required this.modelId,
    required this.thinkingLevel,
    required this.instructions,
    required this.models,
    required this.styles,
    required this.prompts,
  });

  final bool fullscreen;
  final Style? existing;
  final String? modelId;
  final ThinkingLevel? thinkingLevel;
  final String instructions;
  final ModelProvider models;
  final StyleProvider styles;
  final SystemPromptProvider prompts;

  @override
  State<StyleEditor> createState() => _StyleEditorState();
}

class _StyleEditorState extends State<StyleEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _instructionsController;
  late String? _modelId;
  late ThinkingLevel? _thinking;
  late bool _isDefault;
  bool _saving = false;
  bool _aiPending = false;
  String? _error;
  // A retry after a refresh/default-model failure must not create a second style.
  Style? _saved;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _instructionsController = TextEditingController(text: widget.instructions);
    _modelId = widget.modelId;
    _thinking = widget.thinkingLevel;
    _isDefault = widget.existing?.isDefault ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (_saving || _aiPending || name.isEmpty || _modelId == null) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      final content = _instructionsController.text.trim();
      _saved ??= existing == null
          ? await widget.styles.createStyle(
              name: name,
              modelId: _modelId!,
              thinkingLevel: _thinking,
              systemPromptContent: content,
              isDefault: _isDefault,
            )
          : await widget.styles.updateStyle(
              existing.id,
              name: name,
              modelId: _modelId!,
              thinkingLevel: _thinking,
              setThinkingLevel: true,
              systemPromptContent: content,
              isDefault: _isDefault,
            );
      final saved = _saved;
      if (saved == null) {
        if (mounted) setState(() => _error = l.styleSaveFailed);
        return;
      }
      await widget.prompts.refresh();
      if (widget.prompts.error != null) {
        if (mounted) setState(() => _error = l.styleSavedSyncFailed);
        return;
      }
      if (saved.isDefault &&
          !await widget.models.setDefaultModel(saved.modelId)) {
        if (mounted) setState(() => _error = l.styleSavedSyncFailed);
        return;
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _saved == null
              ? l.styleSaveFailed
              : l.styleSavedSyncFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final models = widget.models.availableModels;
    final model = models.where((m) => m.id == _modelId).firstOrNull;
    final editable = !_saving && _saved == null && !_aiPending;
    final isNarrow = widget.fullscreen;
    final title = widget.existing == null ? l.styleNew : l.titleEditStyle;
    void close() => Navigator.of(context).pop(_saved != null);
    final saveButton = FilledButton(
      key: const ValueKey('save_style_confirm'),
      onPressed:
          _saving ||
              _aiPending ||
              _nameController.text.trim().isEmpty ||
              model == null
          ? null
          : _submit,
      child: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(_saved == null ? l.save : l.retry),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('style_name_field'),
          controller: _nameController,
          enabled: editable,
          autofocus: !isNarrow,
          maxLength: 100,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l.labelName,
            hintText: l.hintDeepWorkQuickAnswers,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('style_instructions_field'),
          controller: _instructionsController,
          enabled: editable,
          minLines: isNarrow ? 8 : 4,
          maxLines: isNarrow ? 16 : 8,
          decoration: InputDecoration(
            labelText: l.styleInstructions,
            hintText: l.styleInstructionsHint,
            alignLabelWithHint: true,
          ),
        ),
        StyleInstructionsAssistant(
          controller: _instructionsController,
          prompts: widget.prompts,
          modelId: model?.id,
          enabled: !_saving && _saved == null,
          onPendingChanged: (pending) => setState(() => _aiPending = pending),
        ),
        if (widget.prompts.templates.isNotEmpty)
          ExpansionTile(
            title: Text(l.styleUseExistingPrompt),
            tilePadding: EdgeInsets.zero,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('style_existing_prompt'),
                isExpanded: true,
                hint: Text(l.styleUseExistingPrompt),
                items: [
                  for (final t in widget.prompts.templates)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(t.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: editable
                    ? (id) {
                        final template = widget.prompts.templates.firstWhere(
                          (t) => t.id == id,
                        );
                        _instructionsController.text = template.content;
                      }
                    : null,
              ),
            ],
          ),
        ExpansionTile(
          key: const ValueKey('style_advanced_settings'),
          title: Text(l.styleModelAndThinking),
          subtitle: Text(model?.name ?? l.styleSelectModel),
          initiallyExpanded: model == null,
          tilePadding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 200,
              child: StyleModelList(
                models: models,
                selectedId: _modelId,
                enabled: editable,
                onSelect: (id) => setState(() {
                  _modelId = id;
                  final selected = models.firstWhere((m) => m.id == id);
                  final supported = selected.supportedThinkingLevels;
                  if (_thinking != null && !supported.contains(_thinking)) {
                    _thinking =
                        selected.defaultThinkingLevel ?? supported.firstOrNull;
                  }
                }),
              ),
            ),
            const SizedBox(height: 12),
            StyleThinkingControl(
              value: _thinking,
              enabled: editable && model?.supportsThinking == true,
              supported: model?.supportsThinking == true,
              supportedLevels: model?.supportedThinkingLevels ?? const [],
              onChanged: (v) => setState(() => _thinking = v),
            ),
          ],
        ),
        CheckboxListTile(
          value: _isDefault,
          onChanged: editable
              ? (v) => setState(() => _isDefault = v ?? false)
              : null,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l.titleUseForNewChats),
          dense: true,
        ),
        if (_error != null)
          Text(
            _error!,
            key: const ValueKey('style_save_error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
    return PopScope(
      canPop: !_saving,
      child: isNarrow
          ? Scaffold(
              key: const ValueKey('style_editor_page'),
              appBar: AppBar(
                leading: IconButton(
                  key: const ValueKey('style_editor_back'),
                  tooltip: _saved == null ? l.cancel : l.labelClose,
                  icon: const BackButtonIcon(),
                  onPressed: _saving ? null : close,
                ),
                title: Text(title),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: saveButton,
                  ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  child: content,
                ),
              ),
            )
          : AlertDialog(
              title: Text(title),
              scrollable: true,
              content: SizedBox(width: 480, child: content),
              actions: [
                TextButton(
                  onPressed: _saving ? null : close,
                  child: Text(_saved == null ? l.cancel : l.labelClose),
                ),
                saveButton,
              ],
            ),
    );
  }
}
