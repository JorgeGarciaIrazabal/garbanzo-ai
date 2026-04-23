import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import 'conversation_list_widget.dart';
import '../../rooms/pages/room_chat_page.dart';
import '../../rooms/providers/room_provider.dart';
import '../../rooms/widgets/create_room_dialog.dart';
import '../../rooms/widgets/rooms_list_view.dart';

/// Sidebar shown on wide layouts. Contains a Chats / Rooms tab switcher so
/// rooms feel like first-class peers of conversations.
class ChatSidebar extends StatefulWidget {
  const ChatSidebar({
    super.key,
    required this.conversations,
    required this.selectedConversationId,
    required this.onSelectConversation,
    required this.onDeleteConversation,
    required this.onNewChat,
    required this.onTogglePin,
    required this.isLoadingConversations,
  });

  final List<Conversation> conversations;
  final String? selectedConversationId;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<String> onDeleteConversation;
  final VoidCallback onNewChat;
  final ValueChanged<String> onTogglePin;
  final bool isLoadingConversations;

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  int _tab = 0; // 0 = chats, 1 = rooms
  RoomProvider? _roomsProvider;

  RoomProvider _ensureRoomsProvider() {
    final p = _roomsProvider ??= RoomProvider();
    if (p.rooms.isEmpty && !p.loading) p.loadRooms();
    return p;
  }

  @override
  void dispose() {
    _roomsProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Column(
        children: [
          _Tabs(
            value: _tab,
            onChange: (i) {
              setState(() => _tab = i);
              if (i == 1) _ensureRoomsProvider();
            },
          ),
          Expanded(
            child: _tab == 0
                ? ConversationListWidget(
                    conversations: widget.conversations,
                    selectedId: widget.selectedConversationId,
                    onSelect: widget.onSelectConversation,
                    onDelete: widget.onDeleteConversation,
                    onNewChat: widget.onNewChat,
                    onTogglePin: widget.onTogglePin,
                    isLoading: widget.isLoadingConversations,
                    embedded: true,
                  )
                : ChangeNotifierProvider.value(
                    value: _ensureRoomsProvider(),
                    child: const _RoomsTab(),
                  ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        segments: const [
          ButtonSegment(
            value: 0,
            icon: Icon(Icons.chat_bubble_outline, size: 16),
            label: Text('Chats'),
          ),
          ButtonSegment(
            value: 1,
            icon: Icon(Icons.group_outlined, size: 16),
            label: Text('Rooms'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (s) {
          if (s.isNotEmpty) onChange(s.first);
        },
      ),
    );
  }
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab();

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
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final created = await showCreateRoomDialog(
                      context,
                      provider,
                    );
                    if (created != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoomChatPage(roomId: created.id),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('New Room'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                onPressed:
                    provider.loading ? null : () => provider.loadRooms(),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: RoomsListView(
            rooms: provider.rooms,
            loading: provider.loading,
            error: provider.error,
            compact: true,
            onSelect: (room) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoomChatPage(roomId: room.id),
                ),
              );
            },
            onDelete: (room) => provider.deleteRoom(room.id),
            onCreate: () async {
              final created = await showCreateRoomDialog(context, provider);
              if (created != null && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RoomChatPage(roomId: created.id),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
