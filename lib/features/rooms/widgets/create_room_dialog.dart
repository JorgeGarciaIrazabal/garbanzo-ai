import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';
import 'package:garbanzo_ai/features/friends/widgets/friend_picker_field.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Future<Room?> showCreateRoomDialog(
  BuildContext context,
  RoomProvider provider,
) async {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final pickerKey = GlobalKey<FriendPickerFieldState>();

  // Fresh friends for the picker suggestions; best-effort.
  unawaited(context.read<FriendsProvider>().refresh());

  return showAnimatedDialog<Room>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.titleNewRoom),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.labelName,
                hintText: AppLocalizations.of(context)!.hintEGProductBrainstorm,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                )!.labelDescriptionOptional,
              ),
            ),
            const SizedBox(height: 12),
            Consumer<FriendsProvider>(
              builder: (_, friends, _) => FriendPickerField(
                key: pickerKey,
                friends: friends.friends,
                label: 'Invite people',
                onChanged: (_) {},
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
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            pickerKey.currentState?.commitPendingText();
            final emails = pickerKey.currentState?.selectedEmails ?? const [];
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
          child: Text(AppLocalizations.of(context)!.create),
        ),
      ],
    ),
  );
}
