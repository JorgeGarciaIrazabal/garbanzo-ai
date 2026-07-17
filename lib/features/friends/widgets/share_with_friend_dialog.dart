import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';

/// Picker dialog for sharing a style or prompt template with a friend
/// (Idea 9). Lists accepted friends; tapping one sends the share
/// (copy-on-accept on their side) and reports via snackbar.
Future<void> showShareWithFriendDialog(
  BuildContext context, {
  required String kind, // 'style' | 'prompt'
  required String itemId,
  required String itemName,
}) async {
  final provider = context.read<FriendsProvider>();
  final messenger = ScaffoldMessenger.of(context);
  unawaited(provider.refresh());

  await showAnimatedDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Share "$itemName"'),
      content: SizedBox(
        width: 360,
        child: Consumer<FriendsProvider>(
          builder: (_, friends, _) {
            if (friends.friends.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No friends yet — add some from the Friends page first.',
                ),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final f in friends.friends)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(f.displayName.characters.first.toUpperCase()),
                    ),
                    title: Text(f.displayName),
                    subtitle: f.displayName == f.email ? null : Text(f.email),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final ok = await provider.shareItem(
                        kind: kind,
                        itemId: itemId,
                        recipientEmail: f.email,
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Shared "$itemName" with ${f.displayName}'
                                : provider.error ?? 'Failed to share',
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
