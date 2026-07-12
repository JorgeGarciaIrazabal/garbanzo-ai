import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/create_room_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';

/// Bottom-sheet drawer for mobile screens. Contains a Chats / Rooms tab
/// switcher matching the wide-layout sidebar so rooms are equally
/// discoverable on mobile.
///
/// Rooms come from the app-level [RoomProvider]. Selecting a room defaults to
/// an in-shell navigation (`/rooms/:id`); callers hosting the drawer from a
/// room view pass [onSelectRoom]/[onDeleteRoom] so the shell can handle
/// leaving the active room.
void showMobileConversationDrawer({
  required BuildContext context,
  required List<Conversation> conversations,
  required String? selectedId,
  required ValueChanged<String> onSelect,
  required ValueChanged<String> onDelete,
  required VoidCallback onNewChat,
  ValueChanged<String>? onTogglePin,
  ValueChanged<String>? onSelectRoom,
  ValueChanged<String>? onDeleteRoom,
  String? selectedRoomId,
  int initialTab = 0,
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
        return _MobileDrawerBody(
          conversations: conversations,
          selectedId: selectedId,
          onSelect: onSelect,
          onDelete: onDelete,
          onNewChat: onNewChat,
          onTogglePin: onTogglePin,
          onSelectRoom: onSelectRoom,
          onDeleteRoom: onDeleteRoom,
          selectedRoomId: selectedRoomId,
          initialTab: initialTab,
          scrollController: scrollController,
        );
      },
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
    if (_tab == 1) {
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
    final onSelectRoom = widget.onSelectRoom;
    if (onSelectRoom != null) {
      onSelectRoom(roomId);
    } else {
      context.go('/rooms/$roomId');
    }
  }

  void _deleteRoom(String roomId) {
    final onDeleteRoom = widget.onDeleteRoom;
    if (onDeleteRoom != null) {
      onDeleteRoom(roomId);
    } else {
      context.read<RoomProvider>().deleteRoom(roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
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
              selected: {_tab},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() => _tab = s.first);
                if (_tab == 1) _loadRoomsIfEmpty();
              },
            ),
          ),
          Expanded(
            child: _tab == 0 ? _buildChats(context) : _buildRooms(context),
          ),
        ],
      ),
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
              onPressed: () {
                widget.onNewChat();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('New Chat'),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: widget.conversations.length,
            itemBuilder: (context, index) {
              final conversation = widget.conversations[index];
              final isSelected = conversation.id == widget.selectedId;
              return ListTile(
                leading: Icon(
                  conversation.isPinned ? Icons.push_pin : Icons.chat,
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
                  widget.onSelect(conversation.id);
                  Navigator.pop(context);
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onTogglePin != null)
                      IconButton(
                        icon: Icon(
                          conversation.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                        ),
                        tooltip: conversation.isPinned ? 'Unpin' : 'Pin',
                        onPressed: () => widget.onTogglePin!(conversation.id),
                      ),
                    IconButton(
                      tooltip: 'Delete conversation',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => widget.onDelete(conversation.id),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRooms(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final created = await showCreateRoomDialog(
                      context,
                      provider,
                    );
                    if (!context.mounted) return;
                    if (created != null) _selectRoom(created.id);
                  },
                  icon: const Icon(Icons.group_add),
                  label: const Text('New Room'),
                ),
              ),
            ),
            Expanded(
              child: RoomsListView(
                rooms: provider.rooms,
                loading: provider.loading,
                // Shared with the open-room view — don't let an openRoom
                // failure blank a loaded list.
                error: provider.rooms.isEmpty ? provider.error : null,
                selectedId: widget.selectedRoomId,
                compact: true,
                onSelect: (room) => _selectRoom(room.id),
                onDelete: (room) => _deleteRoom(room.id),
              ),
            ),
          ],
        );
      },
    );
  }
}
