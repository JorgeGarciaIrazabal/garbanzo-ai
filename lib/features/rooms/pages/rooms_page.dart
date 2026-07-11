import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/create_room_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';

/// Stand-alone Rooms page. Used when navigating to rooms from outside the
/// chat sidebar (e.g. from the settings drawer entry).
class RoomsPage extends StatelessWidget {
  const RoomsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RoomProvider()..loadRooms(),
      child: const _RoomsPageBody(),
    );
  }
}

class _RoomsPageBody extends StatelessWidget {
  const _RoomsPageBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoomProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: provider.loading ? null : () => provider.loadRooms(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createRoom(context, provider),
        icon: const Icon(Icons.group_add),
        label: const Text('New room'),
      ),
      body: RoomsListView(
        rooms: provider.rooms,
        loading: provider.loading,
        error: provider.error,
        onSelect: (room) => _openRoom(context, room.id),
        onDelete: (room) => provider.deleteRoom(room.id),
        onCreate: () => _createRoom(context, provider),
      ),
    );
  }

  void _openRoom(BuildContext context, String roomId) {
    context.push('/rooms/$roomId');
  }

  Future<void> _createRoom(BuildContext context, RoomProvider provider) async {
    final created = await showCreateRoomDialog(context, provider);
    if (created != null && context.mounted) _openRoom(context, created.id);
  }
}
