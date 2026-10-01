import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class StarButton extends StatelessWidget {
  const StarButton({
    super.key,
    required this.message,
    required this.conversationId,
  });

  final ChatMessage message;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final l10n = AppLocalizations.of(context)!;
    final label = message.isStarred ? l10n.unstarMessage : l10n.starMessage;
    final enabled =
        !chat.isSending &&
        !chat.isUpdatingMessageStar(message.id) &&
        chat.currentConversation?.id == conversationId;
    return MessageActionButton(
      key: ValueKey('star_message_${message.id}'),
      icon: message.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
      label: label,
      tooltip: label,
      highlighted: message.isStarred,
      onTap: !enabled
          ? null
          : () async {
              final saved = await chat.setMessageStar(
                message.id,
                isStarred: !message.isStarred,
              );
              if (!saved &&
                  context.mounted &&
                  chat.currentConversation?.id == conversationId) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.messageStarUpdateFailed)),
                );
              }
            },
    );
  }
}
