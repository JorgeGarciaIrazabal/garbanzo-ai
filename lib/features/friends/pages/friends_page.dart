import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/friends/models/share_models.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';

/// Friends management: send requests by email, act on incoming/outgoing
/// requests, and remove accepted friends.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _emailController = TextEditingController();
  bool _sending = false;

  FriendsProvider get _provider => context.read<FriendsProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.refresh();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _sending = true);
    final status = await _provider.sendRequest(email);
    if (!mounted) return;
    setState(() => _sending = false);
    if (status != null) {
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'accepted'
                ? 'You are now friends with $email'
                : 'Friend request sent to $email',
          ),
        ),
      );
    }
  }

  void _confirmBlock(String email) {
    showAnimatedDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Block $email? Any friendship or pending request between you is '
          'removed, and neither of you can send new requests or add the '
          'other to rooms. You can unblock them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(context).pop();
              await _provider.block(email);
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(Friend friend) {
    showAnimatedDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text(
          'Remove ${friend.displayName} from your friends? '
          'You can send a new request later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(context).pop();
              await _provider.remove(friend.email);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FriendsProvider>();
    final hasAnything =
        provider.friends.isNotEmpty ||
        provider.incomingRequests.isNotEmpty ||
        provider.outgoingRequests.isNotEmpty ||
        provider.incomingShares.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: provider.isLoading ? null : provider.refresh,
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: provider.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _buildAddFriendCard(),
                const SizedBox(height: 8),
                if (provider.isLoading && !hasAnything)
                  // Column, not SkeletonList: its ListView can't nest here.
                  SkeletonPulse(
                    child: Column(
                      children: [
                        for (var i = 0; i < 5; i++) const SkeletonListTile(),
                      ],
                    ),
                  )
                else ...[
                  if (provider.incomingRequests.isNotEmpty) ...[
                    _sectionHeader(
                      context,
                      'Incoming requests',
                      provider.incomingRequests.length,
                    ),
                    ...provider.incomingRequests.map(_buildIncomingTile),
                  ],
                  if (provider.incomingShares.isNotEmpty) ...[
                    _sectionHeader(
                      context,
                      'Shared with you',
                      provider.incomingShares.length,
                    ),
                    ...provider.incomingShares.map(_buildShareTile),
                  ],
                  if (provider.outgoingRequests.isNotEmpty) ...[
                    _sectionHeader(
                      context,
                      'Sent requests',
                      provider.outgoingRequests.length,
                    ),
                    ...provider.outgoingRequests.map(_buildOutgoingTile),
                  ],
                  _sectionHeader(
                    context,
                    'Your friends',
                    provider.friends.length,
                  ),
                  if (provider.friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No friends yet. Send a request by email above.',
                        ),
                      ),
                    )
                  else
                    ...provider.friends.map(_buildFriendTile),
                  if (provider.blocked.isNotEmpty) ...[
                    _sectionHeader(context, 'Blocked', provider.blocked.length),
                    ...provider.blocked.map(_buildBlockedTile),
                  ],
                ],
              ],
            ),
          ),
          if (provider.error != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  title: Text(
                    provider.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: provider.clearError,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddFriendCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add a friend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('friend_email_field'),
                    controller: _emailController,
                    enabled: !_sending,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'friend@example.com',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendRequest(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('send_friend_request_button'),
                  onPressed: _sending ? null : _sendRequest,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        '$title ($count)',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildIncomingTile(FriendRequest request) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.mark_email_unread_outlined),
        title: Text(request.requesterEmail),
        subtitle: const Text('wants to be your friend'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              tooltip: 'Accept',
              onPressed: () => _provider.accept(request),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              tooltip: 'Decline',
              onPressed: () => _provider.decline(request),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => _confirmBlock(request.requesterEmail),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'block', child: Text('Block sender')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutgoingTile(FriendRequest request) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.schedule_send_outlined),
        title: Text(request.addresseeEmail),
        subtitle: const Text('request pending'),
        trailing: IconButton(
          icon: const Icon(Icons.cancel_outlined),
          tooltip: 'Cancel request',
          onPressed: () => _provider.remove(request.addresseeEmail),
        ),
      ),
    );
  }

  Widget _buildFriendTile(Friend friend) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(friend.displayName.characters.first.toUpperCase()),
        ),
        title: Text(friend.displayName),
        subtitle: friend.fullName != null && friend.fullName!.isNotEmpty
            ? Text(friend.email)
            : null,
        trailing: PopupMenuButton<String>(
          tooltip: 'Friend actions',
          onSelected: (action) => action == 'remove'
              ? _confirmRemove(friend)
              : _confirmBlock(friend.email),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'remove', child: Text('Remove friend')),
            PopupMenuItem(value: 'block', child: Text('Block')),
          ],
        ),
      ),
    );
  }

  Widget _buildShareTile(SharedItem item) {
    final noun = item.kind == 'style' ? 'style' : 'prompt template';
    return Card(
      child: ListTile(
        leading: Icon(
          item.kind == 'style' ? Icons.palette_outlined : Icons.notes_outlined,
        ),
        title: Text('"${item.name}" ($noun)'),
        subtitle: Text('from ${item.senderEmail}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              tooltip: 'Accept share',
              onPressed: () async {
                final ok = await _provider.acceptShare(item);
                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"${item.name}" added to your ${noun}s'),
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              tooltip: 'Decline share',
              onPressed: () => _provider.declineShare(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedTile(Friend user) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.block),
        title: Text(user.displayName),
        subtitle: user.fullName != null && user.fullName!.isNotEmpty
            ? Text(user.email)
            : null,
        trailing: TextButton(
          onPressed: () => _provider.unblock(user.email),
          child: const Text('Unblock'),
        ),
      ),
    );
  }
}
