import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/friends/models/share_models.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

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
        title: Text(AppLocalizations.of(context)!.titleBlockUser),
        content: Text(
          'Block $email? Any friendship or pending request between you is '
          'removed, and neither of you can send new requests or add the '
          'other to rooms. You can unblock them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(context).pop();
              await _provider.block(email);
            },
            child: Text(AppLocalizations.of(context)!.block),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(Friend friend) {
    showAnimatedDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleRemoveFriend),
        content: Text(
          'Remove ${friend.displayName} from your friends? '
          'You can send a new request later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(context).pop();
              await _provider.remove(friend.email);
            },
            child: Text(AppLocalizations.of(context)!.remove),
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
        title: Text(AppLocalizations.of(context)!.titleFriends),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context)!.tooltipRefresh,
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
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          AppLocalizations.of(context)!.messageNoFriendsYet,
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
              AppLocalizations.of(context)!.messageAddAFriend,
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
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(
                        context,
                      )!.hintFriendExampleCom,
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
                  label: Text(AppLocalizations.of(context)!.labelSend),
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
        subtitle: Text(AppLocalizations.of(context)!.wantsToBeYourFriend),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              tooltip: AppLocalizations.of(context)!.tooltipAccept,
              onPressed: () => _provider.accept(request),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              tooltip: AppLocalizations.of(context)!.tooltipDecline,
              onPressed: () => _provider.decline(request),
            ),
            PopupMenuButton<String>(
              tooltip: AppLocalizations.of(context)!.tooltipMore,
              onSelected: (_) => _confirmBlock(request.requesterEmail),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: AppLocalizations.of(context)!.blockLowercase,
                  child: Text(AppLocalizations.of(context)!.blockSender),
                ),
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
        subtitle: Text(AppLocalizations.of(context)!.titleRequestPending),
        trailing: IconButton(
          icon: const Icon(Icons.cancel_outlined),
          tooltip: AppLocalizations.of(context)!.tooltipCancelRequest,
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
          tooltip: AppLocalizations.of(context)!.tooltipFriendActions,
          onSelected: (action) => action == 'remove'
              ? _confirmRemove(friend)
              : _confirmBlock(friend.email),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: AppLocalizations.of(context)!.removeLowercase,
              child: Text(AppLocalizations.of(context)!.removeFriend),
            ),
            PopupMenuItem(
              value: AppLocalizations.of(context)!.blockLowercase,
              child: Text(AppLocalizations.of(context)!.block),
            ),
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
              tooltip: AppLocalizations.of(context)!.tooltipAcceptShare,
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
              tooltip: AppLocalizations.of(context)!.tooltipDeclineShare,
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
          child: Text(AppLocalizations.of(context)!.unblock),
        ),
      ),
    );
  }
}
