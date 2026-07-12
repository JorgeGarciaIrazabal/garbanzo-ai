import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/widgets/conversation_list_widget.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/create_room_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';

/// Sidebar shown on wide layouts. Contains a Chats / Rooms tab switcher so
/// rooms feel like first-class peers of conversations.
///
/// Room selection is handled by the shell ([onSelectRoom]) which swaps the
/// content pane in place — the sidebar itself never navigates. Rooms come
/// from the app-level [RoomProvider].
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
    required this.onSelectRoom,
    required this.onDeleteRoom,
    this.selectedRoomId,
    this.initialTab = 0,
  });

  final List<Conversation> conversations;
  final String? selectedConversationId;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<String> onDeleteConversation;
  final VoidCallback onNewChat;
  final ValueChanged<String> onTogglePin;
  final bool isLoadingConversations;
  final ValueChanged<String> onSelectRoom;
  final ValueChanged<String> onDeleteRoom;
  final String? selectedRoomId;

  /// 0 = chats, 1 = rooms. Set to 1 when the shell is showing a room so a
  /// deep link lands with the matching tab open.
  final int initialTab;

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    if (_tab == 1) {
      // Deferred: loadRooms notifies listeners, which is illegal mid-build.
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
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          _Tabs(
            value: _tab,
            onChange: (i) {
              setState(() => _tab = i);
              if (i == 1) _loadRoomsIfEmpty();
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
                : _RoomsTab(
                    selectedRoomId: widget.selectedRoomId,
                    onSelectRoom: widget.onSelectRoom,
                    onDeleteRoom: widget.onDeleteRoom,
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
                  label: const Text('New Room'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
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
            // The provider is shared with the open-room view, so `error` may
            // be an openRoom failure — don't let it blank a loaded list.
            error: provider.rooms.isEmpty ? provider.error : null,
            selectedId: selectedRoomId,
            compact: true,
            onSelect: (room) => onSelectRoom(room.id),
            onDelete: (room) => onDeleteRoom(room.id),
            onCreate: () => _create(context),
          ),
        ),
      ],
    );
  }
}
