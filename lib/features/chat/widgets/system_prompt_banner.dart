import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_editor_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Collapsible banner shown at the top of a conversation thread that
/// displays the active system prompt (per-conversation override or the
/// user's global default) and lets the user edit it.
class SystemPromptBanner extends StatefulWidget {
  const SystemPromptBanner({super.key});

  @override
  State<SystemPromptBanner> createState() => _SystemPromptBannerState();
}

class _SystemPromptBannerState extends State<SystemPromptBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final promptProvider = context.watch<SystemPromptProvider>();

    final conversation = chatProvider.currentConversation;
    if (conversation == null) return const SizedBox.shrink();

    final convPrompt = conversation.systemPrompt;
    final userDefault = promptProvider.userDefault;

    String? activePrompt;
    String sourceLabel;
    if (convPrompt != null && convPrompt.isNotEmpty) {
      activePrompt = convPrompt;
      sourceLabel = 'Conversation override';
    } else if (userDefault != null && userDefault.isNotEmpty) {
      activePrompt = userDefault;
      sourceLabel = 'Global default';
    } else {
      activePrompt = null;
      sourceLabel = 'No system prompt';
    }

    Future<void> edit() async {
      final result = await SystemPromptEditorDialog.show(
        context,
        initialContent: convPrompt,
        title: AppLocalizations.of(context)!.titleConversationSystemPrompt,
        subtitle: AppLocalizations.of(
          context,
        )!.titleOverridesYourGlobalDefaultForThis,
      );
      if (result == null || result.isCancelled) return;
      if (result.isClear) {
        await chatProvider.updateConversation(clearSystemPrompt: true);
      } else {
        await chatProvider.updateConversation(systemPrompt: result.content);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.labelSystemPrompt,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      sourceLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: AppLocalizations.of(context)!.tooltipEdit,
                    onPressed: edit,
                    visualDensity: VisualDensity.compact,
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                activePrompt ??
                    'No system prompt is active for this conversation.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
