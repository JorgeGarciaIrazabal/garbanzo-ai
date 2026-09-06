import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/mute_sheet.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/create_room_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/search_results_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/search_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

void showMobileConversationDrawer({
  required BuildContext context,
  required List<Conversation> conversations,
  required String? selectedId,
  required ValueChanged<String> onSelect,
  required ValueChanged<String> onDelete,
  required VoidCallback onNewChat,
  ValueChanged<String>? onTogglePin,
  void Function(String conversationId, String duration)? onMuteConversation,
  ValueChanged<String>? onSelectRoom,
  ValueChanged<String>? onDeleteRoom,
  String? selectedRoomId,
  int initialTab = 1,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => _MobileDrawerBody(
        conversations: conversations,
        selectedId: selectedId,
        onSelect: onSelect,
        onDelete: onDelete,
        onNewChat: onNewChat,
        onTogglePin: onTogglePin,
        onMuteConversation: onMuteConversation,
        onSelectRoom: onSelectRoom,
        onDeleteRoom: onDeleteRoom,
        selectedRoomId: selectedRoomId,
        initialTab: initialTab,
        scrollController: scrollController,
      ),
    ),
  );
}

class _MobileDrawerBody extends StatefulWidget {
  const _MobileDrawerBody({
    required this.conversations,
    required this.selectedId,
    required this.onSelect,
    required this.onDelete,
    required this.onNewChat,
    required this.onTogglePin,
    required this.onMuteConversation,
    required this.onSelectRoom,
    required this.onDeleteRoom,
    required this.selectedRoomId,
    required this.initialTab,
    required this.scrollController,
  });

  final List<Conversation> conversations;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onNewChat;
  final ValueChanged<String>? onTogglePin;
  final void Function(String conversationId, String duration)?
  onMuteConversation;
  final ValueChanged<String>? onSelectRoom;
  final ValueChanged<String>? onDeleteRoom;
  final String? selectedRoomId;
  final int initialTab;
  final ScrollController scrollController;

  @override
  State<_MobileDrawerBody> createState() => _MobileDrawerBodyState();
}

class _MobileDrawerBodyState extends State<_MobileDrawerBody> {
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

  void _selectRoom(String roomId) {
    Navigator.pop(context);
    final cb = widget.onSelectRoom;
    if (cb != null) {
      cb(roomId);
    } else {
      context.go('/rooms/$roomId');
    }
  }

  void _deleteRoom(String roomId) {
    final cb = widget.onDeleteRoom;
    if (cb != null) {
      cb(roomId);
    } else {
      context.read<RoomProvider>().deleteRoom(roomId);
    }
  }

  Future<void> _showMuteSheet(BuildContext context, Conversation c) async {
    final apply = widget.onMuteConversation;
    if (apply == null) return;
    final d = await showMuteSheet(
      context: context,
      name: c.displayTitle,
      mutedUntil: c.mutedUntil,
    );
    if (d != null) {
      apply(c.id, d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: _MobileNavigationTabs(
                value: _tab,
                topicsLabel: l10n.topics,
                threadsLabel: l10n.threads,
                roomsLabel: l10n.labelRooms,
                onChange: (tab) {
                  setState(() => _tab = tab);
                  if (tab == 2) _loadRoomsIfEmpty();
                },
              ),
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
            Expanded(
              child: switch (_tab) {
                0 => _buildTopics(context),
                1 => _buildChats(context),
                _ => _buildRooms(context),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopics(BuildContext context) {
    final topics = context.watch<TopicDiscoveryProvider>();
    final l10n = AppLocalizations.of(context)!;
    void popAndPrimary() {
      Navigator.pop(context);
      context.read<ChatProvider>().enterPrimaryConversation();
    }

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.tonalIcon(
          onPressed: popAndPrimary,
          icon: const Icon(Icons.forum_outlined),
          label: Text(l10n.primaryChat),
        ),
        const SizedBox(height: 12),
        ListTile(
          key: const ValueKey('mobile_new_topic'),
          leading: const Icon(Icons.add_comment_outlined),
          title: Text(l10n.newTopic),
          subtitle: Text(l10n.topicFocusHint),
          onTap: () {
            topics.startNewTopic();
            popAndPrimary();
          },
        ),
        if (topics.selectedTopic != null) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: Text(topics.selectedTopic!.label),
            subtitle: Text(l10n.currentTopic),
            onTap: popAndPrimary,
          ),
        ],
      ],
    );
  }

  Widget _buildChats(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('mobile_new_thread'),
              onPressed: () {
                Navigator.pop(context);
                widget.onNewChat();
              },
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context)!.newThread),
            ),
          ),
        ),
        const SearchWidget(autofocus: false),
        Expanded(
          child: Consumer<SearchProvider>(
            builder: (context, search, _) {
              if (search.searchQuery.isNotEmpty) {
                return SearchResultsWidget(
                  onResultSelected: () => Navigator.of(context).pop(),
                );
              }
              return ListView.builder(
                controller: widget.scrollController,
                itemCount: widget.conversations.length,
                itemBuilder: (context, index) {
                  final c = widget.conversations[index];
                  final isSelected = c.id == widget.selectedId;
                  final cs = Theme.of(context).colorScheme;
                  final l10n = AppLocalizations.of(context)!;
                  return ListTile(
                    leading: Icon(
                      c.isPinned ? Icons.push_pin : Icons.chat,
                      color: isSelected ? cs.primary : null,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (c.isMuted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            key: ValueKey('conversation_muted_glyph'),
                            Icons.notifications_off,
                            size: 14,
                            semanticLabel: l10n.messageRoomMuted,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      l10n.messageCount(c.messageCount),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    selected: isSelected,
                    onTap: () {
                      widget.onSelect(c.id);
                      Navigator.pop(context);
                    },
                    onLongPress: widget.onMuteConversation == null
                        ? null
                        : () => _showMuteSheet(context, c),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onTogglePin != null)
                          IconButton(
                            icon: Icon(
                              c.isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                            ),
                            tooltip: c.isPinned ? 'Unpin' : 'Pin',
                            onPressed: () => widget.onTogglePin!(c.id),
                          ),
                        IconButton(
                          tooltip: 'Delete conversation',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => widget.onDelete(c.id),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRooms(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, p, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final created = await showCreateRoomDialog(context, p);
                  if (!context.mounted || created == null) return;
                  _selectRoom(created.id);
                },
                icon: const Icon(Icons.group_add),
                label: Text(AppLocalizations.of(context)!.labelNewRoom),
              ),
            ),
          ),
          Expanded(
            child: RoomsListView(
              rooms: p.rooms,
              loading: p.loading,
              error: p.rooms.isEmpty ? p.error : null,
              selectedId: widget.selectedRoomId,
              compact: true,
              onSelect: (r) => _selectRoom(r.id),
              onDelete: (r) => _deleteRoom(r.id),
              onMute: (r, d) => p.setMute(r.id, d),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileNavigationTabs extends StatelessWidget {
  const _MobileNavigationTabs({
    required this.value,
    required this.topicsLabel,
    required this.threadsLabel,
    required this.roomsLabel,
    required this.onChange,
  });

  final int value;
  final String topicsLabel;
  final String threadsLabel;
  final String roomsLabel;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tabs = [
      (
        label: topicsLabel,
        icon: Icons.auto_awesome_outlined,
        key: 'mobile_drawer_tab_topics',
      ),
      (
        label: threadsLabel,
        icon: Icons.chat_bubble_outline,
        key: 'mobile_drawer_tab_threads',
      ),
      (
        label: roomsLabel,
        icon: Icons.group_outlined,
        key: 'mobile_drawer_tab_rooms',
      ),
    ];
    return Semantics(
      container: true,
      label: '$topicsLabel, $threadsLabel, $roomsLabel',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _MobileNavigationTab(
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

class _MobileNavigationTab extends StatelessWidget {
  const _MobileNavigationTab({
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
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: fg,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
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
