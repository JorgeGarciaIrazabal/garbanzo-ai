import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/rooms/pages/room_chat_page.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/create_room_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';

/// Bottom-sheet drawer for mobile screens. Contains a Chats / Rooms tab
/// switcher matching the wide-layout sidebar so rooms are equally
/// discoverable on mobile.
void showMobileConversationDrawer({
  required BuildContext context,
  required List<Conversation> conversations,
  required String? selectedId,
  required ValueChanged<String> onSelect,
  required ValueChanged<String> onDelete,
  required VoidCallback onNewChat,
  ValueChanged<String>? onTogglePin,
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
    required this.scrollController,
  });

  final List<Conversation> conversations;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onNewChat;
  final ValueChanged<String>? onTogglePin;
  final ScrollController scrollController;

  @override
  State<_MobileDrawerBody> createState() => _MobileDrawerBodyState();
}

class _MobileDrawerBodyState extends State<_MobileDrawerBody> {
  int _tab = 0;
  RoomProvider? _rooms;

  RoomProvider _ensureRoomsProvider() {
    final p = _rooms ??= RoomProvider();
    if (p.rooms.isEmpty && !p.loading) p.loadRooms();
    return p;
  }

  @override
  void dispose() {
    _rooms?.dispose();
    super.dispose();
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
                if (_tab == 1) _ensureRoomsProvider();
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
    final rooms = _ensureRoomsProvider();
    return ChangeNotifierProvider.value(
      value: rooms,
      child: Consumer<RoomProvider>(
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
                      if (created != null) {
                        Navigator.pop(context);
                        unawaited(
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RoomChatPage(roomId: created.id),
                            ),
                          ),
                        );
                      }
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
                  error: provider.error,
                  compact: true,
                  onSelect: (room) {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RoomChatPage(roomId: room.id),
                      ),
                    );
                  },
                  onDelete: (room) => provider.deleteRoom(room.id),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
