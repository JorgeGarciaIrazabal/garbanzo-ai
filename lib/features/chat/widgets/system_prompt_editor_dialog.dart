import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/services/system_prompt_service.dart';
import 'package:garbanzo_ai/features/friends/widgets/share_with_friend_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Result returned from [SystemPromptEditorDialog].
///
///  * `content == null`  → dialog was cancelled (caller should do nothing).
///  * `content == ''`    → user explicitly cleared the prompt.
///  * `content != null && content.isNotEmpty` → new prompt to apply.
class SystemPromptEditorResult {
  const SystemPromptEditorResult({this.content});
  final String? content;

  bool get isClear => content == '';
  bool get isCancelled => content == null;
}

/// Modal that lets the user pick a template, edit a system prompt, and
/// optionally save it to their library.
class SystemPromptEditorDialog extends StatefulWidget {
  const SystemPromptEditorDialog({
    super.key,
    this.initialContent,
    this.title = 'Edit system prompt',
    this.subtitle,
    this.allowClear = true,
  });

  final String? initialContent;
  final String title;
  final String? subtitle;
  final bool allowClear;

  static Future<SystemPromptEditorResult?> show(
    BuildContext context, {
    String? initialContent,
    String title = 'Edit system prompt',
    String? subtitle,
    bool allowClear = true,
  }) {
    // The dialog lives on its own route, above the route-scoped
    // SystemPromptProvider — re-expose the caller's instance to it.
    final promptProvider = context.read<SystemPromptProvider>();
    return showAnimatedDialog<SystemPromptEditorResult>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: promptProvider,
        child: SystemPromptEditorDialog(
          initialContent: initialContent,
          title: title,
          subtitle: subtitle,
          allowClear: allowClear,
        ),
      ),
    );
  }

  @override
  State<SystemPromptEditorDialog> createState() =>
      _SystemPromptEditorDialogState();
}

/// States for the AI generation panel.
enum _AiState { idle, generating, done, error }

class _SystemPromptEditorDialogState extends State<SystemPromptEditorDialog> {
  late final TextEditingController _controller;
  String? _selectedTemplateId;

  // AI generation state
  final SystemPromptService _promptService = SystemPromptService.instance;
  _AiState _aiState = _AiState.idle;
  bool _aiPanelOpen = false;
  final TextEditingController _intentController = TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();
  String? _aiError;
  StreamSubscription<ChatResponseChunk>? _streamSub;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent ?? '');
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _controller.dispose();
    _intentController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  void _applyTemplate(SystemPromptTemplate template) {
    setState(() {
      _controller.text = template.content;
      _selectedTemplateId = template.id;
    });
  }

  /// The selected template, or null if nothing is selected or the selection no
  /// longer exists (deleted here, or dropped by a provider refresh).
  SystemPromptTemplate? _selectedTemplate(List<SystemPromptTemplate> all) {
    if (_selectedTemplateId == null) return null;
    for (final tpl in all) {
      if (tpl.id == _selectedTemplateId) return tpl;
    }
    return null;
  }

  Future<void> _deleteTemplate(SystemPromptTemplate template) async {
    final provider = context.read<SystemPromptProvider>();
    final ok = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${template.name}"?'),
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
    if (ok != true) return;
    await provider.deleteTemplate(template.id);
    if (!mounted) return;
    if (_selectedTemplateId == template.id) {
      setState(() => _selectedTemplateId = null);
    }
  }

  /// Edit a custom template in place: name, description, and content,
  /// pre-seeded from the saved version (not the possibly-diverged editor).
  Future<void> _editTemplate(SystemPromptTemplate template) async {
    final provider = context.read<SystemPromptProvider>();
    final nameController = TextEditingController(text: template.name);
    final descController = TextEditingController(
      text: template.description ?? '',
    );
    final contentController = TextEditingController(text: template.content);

    final saved = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit "${template.name}"'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelName,
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(
                    context,
                  )!.labelDescriptionOptional,
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelPromptContent,
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final name = nameController.text.trim();
    final content = contentController.text.trim();
    if (name.isEmpty || content.isEmpty) return;
    final updated = await provider.updateTemplate(
      template.id,
      name: name,
      content: content,
      description: descController.text.trim(),
    );
    // If the edited template is the one applied to the editor, follow it.
    if (updated != null && mounted && _selectedTemplateId == template.id) {
      setState(() => _controller.text = updated.content);
    }
  }

  String? get _currentModel => context.read<ModelProvider>().selectedModelId;

  void _startGenerate() {
    final intent = _intentController.text.trim();
    if (intent.isEmpty) return;

    final existing = _controller.text.trim();
    final feedback = _feedbackController.text.trim();

    setState(() {
      _aiState = _AiState.generating;
      _aiError = null;
    });

    // Clear the text field to show the streamed draft fresh.
    _controller.clear();

    final stream = _promptService.generate(
      intent: intent,
      existingPrompt: existing.isEmpty ? null : existing,
      feedback: feedback.isEmpty ? null : feedback,
      model: _currentModel,
    );

    _streamSub?.cancel();
    _streamSub = stream.listen(
      (chunk) {
        if (chunk.isChunk && chunk.content != null) {
          _controller.text += chunk.content!;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
          setState(() {});
        } else if (chunk.isDone) {
          setState(() => _aiState = _AiState.done);
        } else if (chunk.isError) {
          setState(() {
            _aiState = _AiState.error;
            _aiError = chunk.error ?? 'Generation failed';
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _aiState = _AiState.error;
            _aiError = e.toString();
          });
        }
      },
      onDone: () {
        if (mounted && _aiState == _AiState.generating) {
          setState(() => _aiState = _AiState.done);
        }
      },
    );
  }

  void _cancelGeneration() {
    _streamSub?.cancel();
    _streamSub = null;
    setState(() => _aiState = _AiState.idle);
  }

  void _acceptAiDraft() {
    _streamSub?.cancel();
    _streamSub = null;
    setState(() {
      _aiState = _AiState.idle;
      _aiPanelOpen = false;
      _feedbackController.clear();
    });
  }

  void _discardAiDraft() {
    _streamSub?.cancel();
    _streamSub = null;
    _controller.text = widget.initialContent ?? '';
    setState(() {
      _aiState = _AiState.idle;
      _aiPanelOpen = false;
      _feedbackController.clear();
    });
  }

  Future<void> _saveToLibrary() async {
    final provider = context.read<SystemPromptProvider>();
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    final nameController = TextEditingController();
    final descController = TextEditingController();

    final saved = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleSavePromptToLibrary),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.labelName,
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                )!.labelDescriptionOptional,
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );

    if (saved == true) {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
      final created = await provider.createTemplate(
        name: name,
        content: content,
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );
      if (created != null && mounted) {
        setState(() => _selectedTemplateId = created.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$name" to your library')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final promptProvider = context.watch<SystemPromptProvider>();
    final builtins = promptProvider.builtinTemplates;
    final customs = promptProvider.customTemplates;
    final selected = _selectedTemplate([...builtins, ...customs]);
    final isGenerating = _aiState == _AiState.generating;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.subtitle != null) ...[
                Text(
                  widget.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.templates,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (promptProvider.isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      // DropdownButton asserts that exactly one item matches
                      // the current value, so every item needs a distinct
                      // value and the selection must survive a template being
                      // deleted underneath us — hence _selectedTemplate.
                      initialValue: selected?.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.labelTemplate,
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(AppLocalizations.of(context)!.none),
                        ),
                        for (final tpl in [...builtins, ...customs])
                          DropdownMenuItem<String?>(
                            value: tpl.id,
                            child: Row(
                              children: [
                                Icon(
                                  tpl.isBuiltin
                                      ? Icons.auto_awesome
                                      : Icons.bookmark,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tpl.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) {
                          setState(() => _selectedTemplateId = null);
                          return;
                        }
                        _applyTemplate(
                          [
                            ...builtins,
                            ...customs,
                          ].firstWhere((t) => t.id == id),
                        );
                      },
                    ),
                  ),
                  // Deleting from inside a menu item doesn't work: the item's
                  // tap handler closes the menu out from under the dialog.
                  if (selected != null && !selected.isBuiltin) ...[
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_outlined),
                      tooltip: 'Share "${selected.name}" with a friend',
                      onPressed: () => showShareWithFriendDialog(
                        context,
                        kind: 'prompt',
                        itemId: selected.id,
                        itemName: selected.name,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit "${selected.name}"',
                      onPressed: () => _editTemplate(selected),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete "${selected.name}"',
                      onPressed: () => _deleteTemplate(selected),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                maxLines: 10,
                minLines: 6,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelSystemPrompt,
                  hintText:
                      "e.g. You are a concise, no-nonsense assistant. Give short "
                      "factual answers with examples.",
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                readOnly: isGenerating,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (!isGenerating) ...[
                    TextButton.icon(
                      onPressed: _aiPanelOpen
                          ? null
                          : () {
                              setState(() => _aiPanelOpen = true);
                            },
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: Text(
                        AppLocalizations.of(context)!.labelCreateWithAi,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (isGenerating) ...[
                    TextButton.icon(
                      onPressed: _cancelGeneration,
                      icon: const Icon(Icons.stop, size: 18),
                      label: Text(AppLocalizations.of(context)!.labelStop),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.messageGenerating,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _controller.text.trim().isEmpty
                              ? null
                              : _saveToLibrary,
                          icon: const Icon(
                            Icons.bookmark_add_outlined,
                            size: 18,
                          ),
                          label: Text(
                            AppLocalizations.of(context)!.labelSaveToLibrary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_aiError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _aiError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_aiPanelOpen || _aiState == _AiState.done) ...[
                const SizedBox(height: 8),
                _AiGeneratePanel(
                  intentController: _intentController,
                  feedbackController: _feedbackController,
                  state: _aiState,
                  isFirstGeneration:
                      _aiState == _AiState.idle ||
                      (_aiState == _AiState.done &&
                          _feedbackController.text.isEmpty),
                  onStart: _startGenerate,
                  onAccept: _acceptAiDraft,
                  onDiscard: _discardAiDraft,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowClear && (widget.initialContent ?? '').isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const SystemPromptEditorResult(content: '')),
            child: Text(AppLocalizations.of(context)!.clear),
          ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const SystemPromptEditorResult()),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: isGenerating
              ? null
              : () => Navigator.of(context).pop(
                  SystemPromptEditorResult(content: _controller.text.trim()),
                ),
          child: Text(AppLocalizations.of(context)!.apply),
        ),
      ],
    );
  }
}

class _AiGeneratePanel extends StatelessWidget {
  const _AiGeneratePanel({
    required this.intentController,
    required this.feedbackController,
    required this.state,
    required this.isFirstGeneration,
    required this.onStart,
    required this.onAccept,
    required this.onDiscard,
  });

  final TextEditingController intentController;
  final TextEditingController feedbackController;
  final _AiState state;
  final bool isFirstGeneration;
  final VoidCallback onStart;
  final VoidCallback onAccept;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGenerating = state == _AiState.generating;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_fix_high,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isFirstGeneration ? 'Create with AI' : 'Refine draft',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isFirstGeneration) ...[
            Text(
              AppLocalizations.of(context)!.messageGenerateHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: intentController,
              enabled: !isGenerating,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(
                  context,
                )!.hintSarcasticCodingMentor,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ] else ...[
            Text(
              AppLocalizations.of(context)!.feedbackToApply,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: feedbackController,
              enabled: !isGenerating,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.hintEGMakeItFriendlier,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: isGenerating ? null : onStart,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(isFirstGeneration ? 'Generate' : 'Refine'),
              ),
              if (!isFirstGeneration) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isGenerating ? null : onAccept,
                  child: Text(AppLocalizations.of(context)!.tooltipAccept),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isGenerating ? null : onDiscard,
                  child: Text(AppLocalizations.of(context)!.discard),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
