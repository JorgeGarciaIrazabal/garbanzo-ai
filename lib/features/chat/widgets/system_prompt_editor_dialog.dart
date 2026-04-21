import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/system_prompt_template.dart';
import '../providers/system_prompt_provider.dart';

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
    return showDialog<SystemPromptEditorResult>(
      context: context,
      builder: (_) => SystemPromptEditorDialog(
        initialContent: initialContent,
        title: title,
        subtitle: subtitle,
        allowClear: allowClear,
      ),
    );
  }

  @override
  State<SystemPromptEditorDialog> createState() =>
      _SystemPromptEditorDialogState();
}

class _SystemPromptEditorDialogState extends State<SystemPromptEditorDialog> {
  late final TextEditingController _controller;
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyTemplate(SystemPromptTemplate template) {
    setState(() {
      _controller.text = template.content;
      _selectedTemplateId = template.id;
    });
  }

  Future<void> _saveToLibrary() async {
    final provider = context.read<SystemPromptProvider>();
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    final nameController = TextEditingController();
    final descController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save prompt to library'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
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

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
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
                  child: Text('Templates',
                      style: theme.textTheme.titleSmall),
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
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final tpl in builtins)
                    _TemplateChip(
                      template: tpl,
                      selected: _selectedTemplateId == tpl.id,
                      onSelected: () => _applyTemplate(tpl),
                    ),
                  if (customs.isNotEmpty)
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: theme.dividerColor,
                    ),
                  for (final tpl in customs)
                    _TemplateChip(
                      template: tpl,
                      selected: _selectedTemplateId == tpl.id,
                      onSelected: () => _applyTemplate(tpl),
                      onDelete: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('Delete "${tpl.name}"?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await promptProvider.deleteTemplate(tpl.id);
                        }
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 10,
              minLines: 6,
              decoration: const InputDecoration(
                labelText: 'System prompt',
                hintText:
                    "e.g. You are a concise, no-nonsense assistant. Give short "
                    "factual answers with examples.",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _controller.text.trim().isEmpty
                    ? null
                    : _saveToLibrary,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Save to library'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowClear && (widget.initialContent ?? '').isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const SystemPromptEditorResult(content: ''),
            ),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const SystemPromptEditorResult(),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            SystemPromptEditorResult(content: _controller.text.trim()),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.template,
    required this.selected,
    required this.onSelected,
    this.onDelete,
  });

  final SystemPromptTemplate template;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        selected: selected,
        label: Text(template.name),
        avatar: Icon(
          template.isBuiltin ? Icons.auto_awesome : Icons.bookmark,
          size: 16,
        ),
        onPressed: onSelected,
        onDeleted: onDelete,
        deleteIcon: onDelete == null
            ? null
            : const Icon(Icons.close, size: 16),
        tooltip: template.description,
      ),
    );
  }
}
