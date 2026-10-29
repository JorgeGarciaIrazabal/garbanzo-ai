import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_picker_helpers.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_editor_dialog.dart';
import 'package:garbanzo_ai/features/friends/widgets/share_with_friend_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class StyleModelList extends StatelessWidget {
  const StyleModelList({
    super.key,
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
                AppLocalizations.of(context)!.messageNoModelsAvailable,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ConstrainedBox(
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

class _CapabilityBadges extends StatelessWidget {
  const _CapabilityBadges({required this.model});
  final ModelInfo model;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in StyleCapability.values)
          if (c.of(model) == true)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: c.label,
                child: Icon(c.icon, size: 16, color: cs.onSurfaceVariant),
              ),
            ),
      ],
    );
  }
}

class StyleThinkingControl extends StatelessWidget {
  const StyleThinkingControl({
    super.key,
    required this.value,
    required this.enabled,
    required this.supported,
    required this.supportedLevels,
    required this.onChanged,
  });

  final ThinkingLevel? value;
  final bool enabled;
  final bool supported;
  final List<ThinkingLevel> supportedLevels;
  final ValueChanged<ThinkingLevel?> onChanged;

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
              Text(
                AppLocalizations.of(context)!.labelThinking,
                style: theme.textTheme.titleSmall,
              ),
              if (!supported) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    AppLocalizations.of(
                      context,
                    )!.messageNotSupportedByThisModel,
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
        Wrap(
          key: const ValueKey('thinking_segment'),
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final level in ThinkingLevel.values)
              ChoiceChip(
                label: Text(level.label),
                selected: value == level,
                visualDensity: context.isWide
                    ? VisualDensity.standard
                    : VisualDensity.compact,
                onSelected: enabled && supportedLevels.contains(level)
                    ? (_) => onChanged(level)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class StyleTemplatePicker extends StatelessWidget {
  const StyleTemplatePicker({
    super.key,
    required this.templates,
    required this.selectedId,
    required this.hasCustomPrompt,
    required this.enabled,
    required this.onChanged,
  });

  final List<SystemPromptTemplate> templates;
  final String? selectedId;
  final bool hasCustomPrompt;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  static const _none = '';

  SystemPromptTemplate? get _selected {
    for (final t in templates) {
      if (t.id == selectedId) return t;
    }
    return null;
  }

  Future<void> _newPrompt(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await SystemPromptEditorDialog.show(
      context,
      initialContent: null,
      title: l10n.labelNewPrompt,
      subtitle: l10n.messageNoTemplatesYet,
      allowClear: false,
    );
  }

  Future<void> _editPrompt(
    BuildContext context,
    SystemPromptTemplate template,
  ) async {
    final provider = context.read<SystemPromptProvider>();
    final result = await SystemPromptEditorDialog.show(
      context,
      initialContent: template.content,
      title: template.name,
      allowClear: false,
    );
    if (result == null || result.isCancelled || result.isClear) return;
    final content = result.content;
    if (content == null || content.isEmpty || content == template.content) {
      return;
    }
    await provider.updateTemplate(template.id, content: content);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final matchingTemplate = templates
        .where((t) => t.id == selectedId && !t.isBuiltin)
        .firstOrNull;
    final value = matchingTemplate != null ? selectedId! : _none;
    final selected = _selected;
    final canShare = enabled && selected != null && !selected.isBuiltin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                AppLocalizations.of(context)!.labelPrompt,
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              if (canShare)
                IconButton(
                  icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                  tooltip: AppLocalizations.of(
                    context,
                  )!.tooltipSharePromptWithFriend(selected.name),
                  onPressed: () => showShareWithFriendDialog(
                    context,
                    kind: 'prompt',
                    itemId: selected.id,
                    itemName: selected.name,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              if (enabled && selected != null && !selected.isBuiltin)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: AppLocalizations.of(
                    context,
                  )!.tooltipEditTemplate(selected.name),
                  onPressed: () => _editPrompt(context, selected),
                  visualDensity: VisualDensity.compact,
                ),
              if (enabled)
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: AppLocalizations.of(context)!.labelNewPrompt,
                  onPressed: () => _newPrompt(context),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
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
                DropdownMenuItem(
                  value: _none,
                  child: Text(AppLocalizations.of(context)!.noTemplate),
                ),
                for (final t in templates.where((t) => !t.isBuiltin))
                  DropdownMenuItem(
                    value: t.id,
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note,
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
