import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/rooms/pages/room_chat_page.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/create_room_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';

/// Left sidebar shown inside [RoomChatPage] on wide layouts so users can see
/// (and switch between) all their rooms — mirroring the conversation list in
/// the main chat page.
///
/// Owns its own [RoomProvider] so it's decoupled from the open-room provider
/// hosted by the page.
class RoomsSidebar extends StatefulWidget {
  const RoomsSidebar({
    super.key,
    required this.selectedRoomId,
    this.onBeforeNavigate,
  });

  final String selectedRoomId;

  /// Optional hook fired right before navigating away (e.g. opening another
  /// room or going back to chats). Useful when this sidebar is hosted inside
  /// a bottom sheet so the sheet can be dismissed first.
  final VoidCallback? onBeforeNavigate;

  @override
  State<RoomsSidebar> createState() => _RoomsSidebarState();
}

class _RoomsSidebarState extends State<RoomsSidebar> {
  final _provider = RoomProvider();

  @override
  void initState() {
    super.initState();
    _provider.loadRooms();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  void _openRoom(BuildContext context, String roomId) {
    if (roomId == widget.selectedRoomId) {
      widget.onBeforeNavigate?.call();
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    widget.onBeforeNavigate?.call();
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => RoomChatPage(roomId: roomId)),
    );
  }

  void _backToChats(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    widget.onBeforeNavigate?.call();
    navigator.pop();
  }

  Future<void> _create(BuildContext context) async {
    final created = await showCreateRoomDialog(context, _provider);
    if (created != null && context.mounted) {
      _openRoom(context, created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<RoomProvider>(
        builder: (context, provider, _) {
          final cs = Theme.of(context).colorScheme;
          return Container(
            width: 280,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(
                right: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              children: [
                _Header(onBackToChats: () => _backToChats(context)),
                _NewRoomBar(
                  onCreate: () => _create(context),
                  onRefresh: provider.loading
                      ? null
                      : () => provider.loadRooms(),
                ),
                Expanded(
                  child: RoomsListView(
                    rooms: provider.rooms,
                    loading: provider.loading,
                    error: provider.error,
                    selectedId: widget.selectedRoomId,
                    compact: true,
                    onSelect: (room) => _openRoom(context, room.id),
                    onDelete: (room) => provider.deleteRoom(room.id),
                    onCreate: () => _create(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBackToChats});
  final VoidCallback onBackToChats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onBackToChats,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.arrow_back_ios_new,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Back to chats',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(Icons.group_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Rooms',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewRoomBar extends StatelessWidget {
  const _NewRoomBar({required this.onCreate, required this.onRefresh});
  final VoidCallback onCreate;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.group_add, size: 18),
              label: const Text('New Room'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }
}
