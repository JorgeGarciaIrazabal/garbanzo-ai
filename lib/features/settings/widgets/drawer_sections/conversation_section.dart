import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/section_header.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/tools_picker.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Per-conversation context controls: memory / knowledge-base injection
/// toggles and the tool whitelist. Model and system prompt selection moved
/// to the style picker on the chat screen (the single place to manage a
/// conversation's model + prompt).
class ConversationSection extends StatelessWidget {
  const ConversationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_ContextToggles(), Divider(height: 24), ToolsPicker()],
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
        SectionHeader(
          icon: Icons.tune,
          title: AppLocalizations.of(context)!.titlePersonalContext,
        ),
        if (conversation != null) ...[
          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.titleUseMemory),
            subtitle: const Text(
              'Inject saved memories into this conversation',
            ),
            value: conversation.useMemory,
            onChanged: (value) {
              chatProvider.updateConversation(useMemory: value);
            },
            dense: true,
          ),
          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.titleUseKnowledgeBase),
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
          ListTile(
            title: Text(AppLocalizations.of(context)!.titleMemoryKnowledgeBase),
            subtitle: Text(
              AppLocalizations.of(
                context,
              )!.titleStartAConversationToToggleInjection,
            ),
            dense: true,
            enabled: false,
          ),
      ],
    );
  }
}
