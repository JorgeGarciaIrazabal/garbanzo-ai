import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/mute_sheet.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/search_results_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/search_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Widget displaying a list of conversations.
class ConversationListWidget extends StatelessWidget {
  const ConversationListWidget({
    super.key,
    required this.conversations,
    required this.selectedId,
    required this.onSelect,
    required this.onDelete,
    required this.onNewChat,
    this.onTogglePin,
    this.onMute,
    this.isLoading = false,
    this.embedded = false,
  });

  final List<Conversation> conversations;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onNewChat;
  final ValueChanged<String>? onTogglePin;

  /// Applies a mute choice (`8h` / `1w` / `forever` / `unmute`) to a
  /// conversation. Long-press / right-click only opens the mute sheet when
  /// this is set.
  final void Function(Conversation conversation, String duration)? onMute;

  final bool isLoading;

  /// When true, drop the outer width / border chrome — caller is responsible
  /// for those. Used when this widget is hosted inside a tabbed sidebar.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final body = Column(
      children: [
        // Header with new chat button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNewChat,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(AppLocalizations.of(context)!.labelNewChat),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SearchWidget(),
        // Conversation list or search results
        Expanded(
          child: Consumer<SearchProvider>(
            builder: (context, searchProvider, _) {
              if (searchProvider.searchQuery.isNotEmpty) {
                return const SearchResultsWidget();
              }
              if (isLoading && conversations.isEmpty) {
                return const SkeletonList();
              }
              if (conversations.isEmpty) {
                return _EmptyState(colorScheme: colorScheme);
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  final isSelected = conversation.id == selectedId;

                  return _ConversationListItem(
                    conversation: conversation,
                    isSelected: isSelected,
                    onTap: () => onSelect(conversation.id),
                    onDelete: () => _confirmDelete(context, conversation),
                    onTogglePin: onTogglePin == null
                        ? null
                        : () => onTogglePin!(conversation.id),
                    onMuteMenu: onMute == null
                        ? null
                        : () => _showMuteSheet(context, conversation),
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                  );
                },
              );
            },
          ),
        ),
      ],
    );

    if (embedded) return body;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: body,
    );
  }

  Future<void> _showMuteSheet(
    BuildContext context,
    Conversation conversation,
  ) async {
    final apply = onMute;
    if (apply == null) return;
    final duration = await showMuteSheet(
      context: context,
      name: conversation.displayTitle,
      mutedUntil: conversation.mutedUntil,
    );
    if (duration != null) apply(conversation, duration);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Conversation conversation,
  ) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleDeleteConversation),
        content: Text(
          'Are you sure you want to delete "${conversation.displayTitle}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(AppLocalizations.of(context)!.delete),
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
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
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
    this.onTogglePin,
    this.onMuteMenu,
  });

  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onTogglePin;

  /// Opens the mute sheet — long-press on touch, right-click on desktop.
  final VoidCallback? onMuteMenu;

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final unselectedIcon = isSelected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Material(
      color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // InkWell carries both gestures natively — no wrapper needed.
        onLongPress: onMuteMenu,
        onSecondaryTap: onMuteMenu,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              // Icon (pinned → push-pin, else chat)
              Icon(
                conversation.isPinned ? Icons.push_pin : Icons.chat,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            conversation.displayTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conversation.isMuted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            key: const ValueKey('conversation_muted_glyph'),
                            Icons.notifications_off,
                            size: 14,
                            semanticLabel: AppLocalizations.of(
                              context,
                            )!.messageRoomMuted,
                            color: unselectedIcon,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${conversation.messageCount} message${conversation.messageCount == 1 ? '' : 's'}',
                      style: textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.7,
                              )
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTogglePin != null)
                IconButton(
                  onPressed: onTogglePin,
                  icon: Icon(
                    conversation.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    size: 18,
                  ),
                  tooltip: conversation.isPinned ? 'Unpin' : 'Pin',
                  color: unselectedIcon,
                  visualDensity: VisualDensity.compact,
                ),
              // Delete button
              IconButton(
                tooltip: 'Delete conversation',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: unselectedIcon,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
