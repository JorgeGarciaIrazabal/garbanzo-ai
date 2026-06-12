import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../chat/providers/chat_provider.dart';
import '../../../chat/providers/model_provider.dart';
import '../../../chat/providers/system_prompt_provider.dart';
import '../../../chat/widgets/system_prompt_editor_dialog.dart';
import 'section_header.dart';
import 'tools_picker.dart';

/// Everything scoped to the active conversation: model, system prompt,
/// memory/knowledge-base toggles, and the tool whitelist.
class ConversationSection extends StatelessWidget {
  const ConversationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _ModelTile(),
        Divider(height: 24),
        _SystemPromptTiles(),
        Divider(height: 24),
        _ContextToggles(),
        Divider(height: 24),
        ToolsPicker(),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelProvider = context.watch<ModelProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final models = modelProvider.availableModels;
    final selectedId = modelProvider.selectedModelId;

    String? selectedName;
    for (final model in models) {
      if (model.id == selectedId) {
        selectedName = model.name;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(icon: Icons.smart_toy, title: 'Model'),
        ListTile(
          title: const Text('LLM Model'),
          subtitle: Text(
            selectedName ?? selectedId ?? 'No model selected',
            style: theme.textTheme.bodySmall,
          ),
          dense: true,
          trailing: DropdownButton<String>(
            value: models.any((m) => m.id == selectedId) ? selectedId : null,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: models
                .map((m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        m.name,
                        style: theme.textTheme.bodySmall,
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                modelProvider.selectModel(value);
                if (chatProvider.currentConversation != null) {
                  chatProvider.updateConversation(model: value);
                }
              }
            },
          ),
        ),
      ],
    );
  }
}

class _SystemPromptTiles extends StatelessWidget {
  const _SystemPromptTiles();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final promptProvider = context.watch<SystemPromptProvider>();
    final conversation = chatProvider.currentConversation;
    final convPrompt = conversation?.systemPrompt;
    final userDefault = promptProvider.userDefault;

    final effectivePrompt = (convPrompt?.isNotEmpty ?? false)
        ? convPrompt!
        : (userDefault ?? '');
    final effectiveSource = (convPrompt?.isNotEmpty ?? false)
        ? 'Conversation'
        : (userDefault != null && userDefault.isNotEmpty
            ? 'Global default'
            : 'None');

    Future<void> editConversationPrompt() async {
      if (conversation == null) return;
      final result = await SystemPromptEditorDialog.show(
        context,
        initialContent: convPrompt,
        title: 'Conversation system prompt',
        subtitle:
            'Overrides your global default for this conversation only.',
      );
      if (result == null || result.isCancelled) return;
      if (result.isClear) {
        await chatProvider.updateConversation(clearSystemPrompt: true);
      } else {
        await chatProvider.updateConversation(systemPrompt: result.content);
      }
    }

    Future<void> editUserDefault() async {
      final result = await SystemPromptEditorDialog.show(
        context,
        initialContent: userDefault,
        title: 'Global default system prompt',
        subtitle:
            'Applied to every new conversation unless overridden per-chat.',
      );
      if (result == null || result.isCancelled) return;
      if (result.isClear) {
        await promptProvider.setUserDefault(null);
      } else {
        await promptProvider.setUserDefault(result.content);
      }
    }

    String truncate(String s) =>
        s.length <= 80 ? s : '${s.substring(0, 80)}…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          icon: Icons.assignment_outlined,
          title: 'System Prompt',
        ),
        // Per-conversation
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: const Text('This conversation'),
          subtitle: conversation == null
              ? const Text('Start a conversation to set a prompt')
              : Text(
                  convPrompt == null || convPrompt.isEmpty
                      ? 'Using: $effectiveSource'
                      : truncate(convPrompt),
                  style: theme.textTheme.bodySmall,
                ),
          trailing: conversation == null
              ? null
              : Icon(Icons.edit, size: 18, color: colorScheme.primary),
          enabled: conversation != null,
          dense: true,
          onTap: conversation == null ? null : editConversationPrompt,
        ),
        // Global default
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Global default'),
          subtitle: Text(
            (userDefault == null || userDefault.isEmpty)
                ? 'Not set — using built-in defaults'
                : truncate(userDefault),
            style: theme.textTheme.bodySmall,
          ),
          trailing: Icon(Icons.edit, size: 18, color: colorScheme.primary),
          dense: true,
          onTap: editUserDefault,
        ),
        if (effectivePrompt.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'No system prompt active.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Memory and knowledge-base injection toggles for the active conversation.
class _ContextToggles extends StatelessWidget {
  const _ContextToggles();

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.currentConversation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          icon: Icons.tune,
          title: 'Personal context',
        ),
        if (conversation != null) ...[
          SwitchListTile(
            title: const Text('Use memory'),
            subtitle:
                const Text('Inject saved memories into this conversation'),
            value: conversation.useMemory,
            onChanged: (value) {
              chatProvider.updateConversation(useMemory: value);
            },
            dense: true,
          ),
          SwitchListTile(
            title: const Text('Use knowledge base'),
            subtitle: const Text(
              'Inject relevant document excerpts into this conversation',
            ),
            value: conversation.useKnowledgeBase,
            onChanged: (value) {
              chatProvider.updateConversation(useKnowledgeBase: value);
            },
            dense: true,
          ),
        ] else
          const ListTile(
            title: Text('Memory & knowledge base'),
            subtitle: Text('Start a conversation to toggle injection'),
            dense: true,
            enabled: false,
          ),
      ],
    );
  }
}
