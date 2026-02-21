import 'package:flutter/material.dart';

import '../models/conversation.dart';

/// Widget displaying a list of conversations.
class ConversationListWidget extends StatelessWidget {
  const ConversationListWidget({
    super.key,
    required this.conversations,
    required this.selectedId,
    required this.onSelect,
    required this.onDelete,
    required this.onNewChat,
    this.isLoading = false,
  });

  final List<Conversation> conversations;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onNewChat;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header with new chat button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onNewChat,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Chat'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Conversation list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : conversations.isEmpty
                    ? _EmptyState(colorScheme: colorScheme)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = conversations[index];
                          final isSelected = conversation.id == selectedId;

                          return _ConversationListItem(
                            conversation: conversation,
                            isSelected: isSelected,
                            onTap: () => onSelect(conversation.id),
                            onDelete: () => _confirmDelete(
                              context,
                              conversation,
                            ),
                            colorScheme: colorScheme,
                            textTheme: theme.textTheme,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: Text(
          'Are you sure you want to delete "${conversation.displayTitle}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onDelete(conversation.id);
    }
  }
}

/// Empty state when no conversations exist.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual conversation list item.
class _ConversationListItem extends StatelessWidget {
  const _ConversationListItem({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.colorScheme,
    required this.textTheme,
  });

  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              // Icon
              Icon(
                Icons.chat,
                size: 20,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              // Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.displayTitle,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${conversation.messageCount} message${conversation.messageCount == 1 ? '' : 's'}',
                      style: textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                            : colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: isSelected
                    ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                    : colorScheme.onSurfaceVariant.withOpacity(0.5),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
