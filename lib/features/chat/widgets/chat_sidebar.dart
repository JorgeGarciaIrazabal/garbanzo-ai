import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/chat/widgets/conversation_list_widget.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/create_room_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Sidebar shown on wide layouts. Contains Topics / Threads / Rooms.
class ChatSidebar extends StatefulWidget {
  const ChatSidebar({
    super.key,
    required this.conversations,
    required this.selectedConversationId,
    required this.onSelectConversation,
    required this.onDeleteConversation,
    required this.onNewChat,
    required this.onTogglePin,
    this.onMuteConversation,
    required this.isLoadingConversations,
    required this.onSelectRoom,
    required this.onDeleteRoom,
    required this.onOpenPrimary,
    this.selectedRoomId,
    this.initialTab = 1,
  });

  final List<Conversation> conversations;
  final String? selectedConversationId;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<String> onDeleteConversation;
  final VoidCallback onNewChat;
  final ValueChanged<String> onTogglePin;
  final void Function(String conversationId, String duration)?
  onMuteConversation;
  final bool isLoadingConversations;
  final ValueChanged<String> onSelectRoom;
  final ValueChanged<String> onDeleteRoom;
  final String? selectedRoomId;
  final VoidCallback onOpenPrimary;
  final int initialTab;

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    if (_tab == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadRoomsIfEmpty();
      });
    }
  }

  void _loadRoomsIfEmpty() {
    final rooms = context.read<RoomProvider>();
    if (rooms.rooms.isEmpty && !rooms.loading) rooms.loadRooms();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 280,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Material(
        key: const ValueKey('chat_sidebar_material'),
        color: cs.surfaceContainerLow,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              child: _Tabs(
                value: _tab,
                onChange: (i) {
                  setState(() => _tab = i);
                  if (i == 2) _loadRoomsIfEmpty();
                },
              ),
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
            Expanded(
              child: switch (_tab) {
                0 => _TopicsTab(onOpenPrimary: widget.onOpenPrimary),
                1 => ConversationListWidget(
                  conversations: widget.conversations,
                  selectedId: widget.selectedConversationId,
                  onSelect: widget.onSelectConversation,
                  onDelete: widget.onDeleteConversation,
                  onNewChat: widget.onNewChat,
                  onTogglePin: widget.onTogglePin,
                  onMute: widget.onMuteConversation == null
                      ? null
                      : (c, d) => widget.onMuteConversation!(c.id, d),
                  isLoading: widget.isLoadingConversations,
                  embedded: true,
                  newConversationLabel: AppLocalizations.of(context)!.newThread,
                ),
                _ => _RoomsTab(
                  selectedRoomId: widget.selectedRoomId,
                  onSelectRoom: widget.onSelectRoom,
                  onDeleteRoom: widget.onDeleteRoom,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.value, required this.onChange});
  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tabs = [
      (
        key: 'sidebar_tab_topics',
        label: l10n.topics,
        icon: Icons.auto_awesome_outlined,
      ),
      (
        key: 'sidebar_tab_threads',
        label: l10n.threads,
        icon: Icons.chat_bubble_outline,
      ),
      (
        key: 'sidebar_tab_rooms',
        label: l10n.labelRooms,
        icon: Icons.group_outlined,
      ),
    ];
    return Semantics(
      container: true,
      label: '${l10n.topics}, ${l10n.threads}, ${l10n.labelRooms}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _NavigationTab(
                key: ValueKey(tabs[i].key),
                label: tabs[i].label,
                icon: tabs[i].icon,
                selected: value == i,
                onTap: () => onChange(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavigationTab extends StatelessWidget {
  const _NavigationTab({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 19, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.arrow_forward_rounded, size: 18, color: fg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicsTab extends StatelessWidget {
  const _TopicsTab({required this.onOpenPrimary});
  final VoidCallback onOpenPrimary;

  Widget _card(
    BuildContext context, {
    required Color color,
    required Widget child,
  }) => Card(elevation: 0, color: color, child: child);

  @override
  Widget build(BuildContext context) {
    final topics = context.watch<TopicDiscoveryProvider>();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final selected = topics.selectedTopic;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('open_primary_chat'),
          onPressed: onOpenPrimary,
          icon: const Icon(Icons.forum_outlined),
          label: Text(l10n.primaryChat),
        ),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: l10n.newTopic,
          child: _card(
            context,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.48),
            child: ListTile(
              key: const ValueKey('new_topic_sidebar'),
              leading: const Icon(Icons.add_comment_outlined),
              title: Text(l10n.newTopic),
              subtitle: Text(l10n.topicFocusHint),
              onTap: () {
                topics.startNewTopic();
                onOpenPrimary();
              },
            ),
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.currentTopic,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          _card(
            context,
            color: cs.secondaryContainer.withValues(alpha: 0.45),
            child: ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: Text(selected.label),
              subtitle: Text(
                selected.contextStatus == TopicContextStatus.preparing
                    ? l10n.preparingContext
                    : l10n.activeNow,
              ),
              onTap: onOpenPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab({
    required this.selectedRoomId,
    required this.onSelectRoom,
    required this.onDeleteRoom,
  });

  final String? selectedRoomId;
  final ValueChanged<String> onSelectRoom;
  final ValueChanged<String> onDeleteRoom;

  Future<void> _create(BuildContext context) async {
    final provider = context.read<RoomProvider>();
    final created = await showCreateRoomDialog(context, provider);
    if (created != null && context.mounted) onSelectRoom(created.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoomProvider>();
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: Text(AppLocalizations.of(context)!.labelNewRoom),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: AppLocalizations.of(context)!.tooltipRefresh,
                onPressed: provider.loading ? null : () => provider.loadRooms(),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: RoomsListView(
            rooms: provider.rooms,
            loading: provider.loading,
            error: provider.rooms.isEmpty ? provider.error : null,
            selectedId: selectedRoomId,
            compact: true,
            onSelect: (room) => onSelectRoom(room.id),
            onDelete: (room) => onDeleteRoom(room.id),
            onCreate: () => _create(context),
            onMute: (room, d) => provider.setMute(room.id, d),
          ),
        ),
      ],
    );
  }
}
