import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/pages/room_chat_page.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';

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
            icon: const Icon(Icons.refresh),
            onPressed: provider.loading ? null : () => provider.loadRooms(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, provider),
        icon: const Icon(Icons.add),
        label: const Text('New room'),
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : provider.error != null
              ? Center(child: Text('Error: ${provider.error}'))
              : provider.rooms.isEmpty
                  ? const Center(
                      child: Text('No rooms yet. Create one to get started.'),
                    )
                  : ListView.separated(
                      itemCount: provider.rooms.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = provider.rooms[i];
                        return _RoomTile(
                          room: r,
                          onOpen: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RoomChatPage(roomId: r.id),
                              ),
                            );
                          },
                          onDelete: () => provider.deleteRoom(r.id),
                        );
                      },
                    ),
    );
  }

  Future<void> _showCreateDialog(
      BuildContext context, RoomProvider provider) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final emailsCtrl = TextEditingController();
    final created = await showDialog<Room>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create room'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true,
              ),
              TextField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
              ),
              TextField(
                controller: emailsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Invite emails (comma-separated)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final emails = emailsCtrl.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              try {
                final room = await provider.createRoom(
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  memberEmails: emails,
                );
                if (ctx.mounted) Navigator.of(ctx).pop(room);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (created != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RoomChatPage(roomId: created.id)),
      );
    }
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.onOpen,
    required this.onDelete,
  });

  final Room room;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.group)),
      title: Text(room.name),
      subtitle: Text(
        room.description ??
            '${room.memberCount} member(s) · ${room.agentCount} agent(s)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete room?'),
              content: Text('Delete "${room.name}"? This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok == true) onDelete();
        },
      ),
      onTap: onOpen,
    );
  }
}
