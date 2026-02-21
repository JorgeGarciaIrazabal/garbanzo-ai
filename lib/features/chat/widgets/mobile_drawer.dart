import 'package:flutter/material.dart';

import '../models/conversation.dart';

/// Bottom-sheet drawer for mobile screens showing the conversation list.
void showMobileConversationDrawer({
  required BuildContext context,
  required List<Conversation> conversations,
  required String? selectedId,
  required ValueChanged<String> onSelect,
  required ValueChanged<String> onDelete,
  required VoidCallback onNewChat,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          onNewChat();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New Chat'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final isSelected = conversation.id == selectedId;

                    return ListTile(
                      leading: Icon(
                        Icons.chat,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        conversation.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${conversation.messageCount} messages',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      selected: isSelected,
                      onTap: () {
                        onSelect(conversation.id);
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onDelete(conversation.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
