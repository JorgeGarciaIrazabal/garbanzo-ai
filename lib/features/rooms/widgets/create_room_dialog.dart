import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';

Future<Room?> showCreateRoomDialog(
  BuildContext context,
  RoomProvider provider,
) async {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final emailsCtrl = TextEditingController();

  return showAnimatedDialog<Room>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New room'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Product brainstorm',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailsCtrl,
              decoration: const InputDecoration(
                labelText: 'Invite people (comma-separated emails)',
                hintText: 'alice@example.com, bob@example.com',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can add AI agents from inside the room.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
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
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            final emails = emailsCtrl.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            try {
              final room = await provider.createRoom(
                name: name,
                description: descCtrl.text.trim().isEmpty
                    ? null
                    : descCtrl.text.trim(),
                memberEmails: emails,
              );
              if (ctx.mounted) Navigator.of(ctx).pop(room);
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            }
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
