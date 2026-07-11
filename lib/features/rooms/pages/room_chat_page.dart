import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/reading_column.dart';
import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/core/smart_scroll_controller.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';
import 'package:garbanzo_ai/features/rooms/widgets/add_agent_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/room_message_bubble.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_sidebar.dart';

/// Full-page chat UI for a single multi-person / multi-agent room.
class RoomChatPage extends StatelessWidget {
  const RoomChatPage({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RoomProvider()..openRoom(roomId),
      child: _RoomChatPageBody(roomId: roomId),
    );
  }
}

class _RoomChatPageBody extends StatefulWidget {
  const _RoomChatPageBody({required this.roomId});
  final String roomId;
  @override
  State<_RoomChatPageBody> createState() => _RoomChatPageBodyState();
}

class _RoomChatPageBodyState extends State<_RoomChatPageBody> {
  final _scroll = SmartScrollController();
  RoomProvider? _providerRef;

  @override
  void initState() {
    super.initState();
    _scroll.attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Follow the live streaming bubble as it grows. Agent chunk updates flow
    // through the ValueNotifier (not notifyListeners), so the scroll-follow
    // needs its own listener.
    final provider = context.read<RoomProvider>();
    if (!identical(provider, _providerRef)) {
      _providerRef?.streamingMessage.removeListener(_onStreamingUpdate);
      _providerRef = provider;
      provider.streamingMessage.addListener(_onStreamingUpdate);
    }
  }

  @override
  void dispose() {
    _providerRef?.streamingMessage.removeListener(_onStreamingUpdate);
    _scroll.dispose();
    super.dispose();
  }

  void _onStreamingUpdate() {
    if (mounted) _scroll.followStreaming();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoomProvider>();
    final room = provider.currentRoom;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final me = AuthService.instance.cachedUser?.email;
    final messages = provider.messages;

    final lastSenderIsMe =
        messages.isNotEmpty && messages.last.senderUserId == me;
    _scroll.handleStructural(
      itemCount: messages.length,
      containerId: room?.id,
      forceFollow: lastSenderIsMe,
    );

    final showSidebar = context.isWide;

    final mainColumn = provider.loading && room == null
        ? const SkeletonList(showAvatar: true, itemCount: 6)
        : Column(
            children: [
              if (provider.error != null)
                _ErrorBanner(
                  message: provider.error!,
                  onDismiss: () =>
                      room != null ? provider.openRoom(room.id) : null,
                ),
              _ConnectionBanner(
                state: provider.connectionState,
                onRetry: provider.retryConnection,
              ),
              Expanded(
                child: messages.isEmpty
                    ? _EmptyState(room: room)
                    : Stack(
                        children: [
                          _buildMessageList(provider, room, me),
                          Positioned(
                            right: 16,
                            bottom: 12,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _scroll.showJumpToBottom,
                              builder: (context, show, _) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                child: show
                                    ? FloatingActionButton.small(
                                        heroTag: 'room_jump_to_bottom',
                                        tooltip: 'Jump to latest message',
                                        onPressed: () =>
                                            _scroll.scrollToBottom(),
                                        child: const Icon(
                                          Icons.keyboard_arrow_down,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              _TypingStrip(typingUsers: provider.typingUsers, room: room),
              MessageComposer(
                enabled: room != null,
                hintText: 'Message the room… (use @AgentName or @all)',
                onSend: (text) => provider.sendMessage(text),
                onChanged: provider.handleComposerChanged,
                onBlur: provider.handleComposerBlur,
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              room?.name ?? 'Loading…',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            if (room != null)
              Text(
                _subtitleForRoom(room, provider.onlineUsers.length),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          if (!showSidebar)
            IconButton(
              tooltip: 'All rooms',
              icon: const Icon(Icons.menu_open),
              onPressed: () => _showRoomsDrawer(context),
            ),
          IconButton(
            tooltip: 'Members & agents',
            icon: const Icon(Icons.group_outlined),
            onPressed: room == null ? null : () => _showPanel(context),
          ),
        ],
      ),
      body: showSidebar
          ? Row(
              children: [
                RoomsSidebar(selectedRoomId: widget.roomId),
                Expanded(child: mainColumn),
              ],
            )
          : mainColumn,
    );
  }

  Widget _buildMessageList(RoomProvider provider, Room? room, String? me) {
    final messages = provider.messages;
    return ListView.builder(
      controller: _scroll.controller,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final m = messages[i];

        Widget bubble(RoomMessage msg, {required bool isStreaming}) =>
            ReadingColumn(
              child: RoomMessageBubble(
                message: msg,
                room: room,
                currentUserEmail: me,
                isStreaming: isStreaming,
              ),
            );

        // The in-flight agent bubble subscribes to the streaming channel
        // directly, so per-chunk updates repaint only this one widget instead
        // of the whole list.
        if (m.id == provider.streamingMessageId) {
          return ValueListenableBuilder<RoomMessage?>(
            valueListenable: provider.streamingMessage,
            builder: (context, live, _) => bubble(
              live != null && live.id == m.id ? live : m,
              isStreaming: true,
            ),
          );
        }
        return bubble(m, isStreaming: false);
      },
    );
  }

  void _showRoomsDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, _) => RoomsSidebar(
          selectedRoomId: widget.roomId,
          // Dismiss the bottom sheet before any navigation so we don't push
          // routes on top of (or pop) the modal route itself.
          onBeforeNavigate: () {
            if (Navigator.of(sheetCtx).canPop()) Navigator.of(sheetCtx).pop();
          },
        ),
      ),
    );
  }

  String _subtitleForRoom(Room room, int onlineCount) {
    final memberWord = room.memberCount == 1 ? 'member' : 'members';
    final agentWord = room.agentCount == 1 ? 'agent' : 'agents';
    final base =
        '${room.memberCount} $memberWord · ${room.agentCount} $agentWord';
    if (onlineCount > 0) return '$base · $onlineCount online';
    return base;
  }

  void _showPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<RoomProvider>(),
        child: const _MembersAgentsPanel(),
      ),
    );
  }
}

/// Slim banner shown while the socket is reconnecting or has given up.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.state, required this.onRetry});

  final RoomConnectionState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (state) {
      case RoomConnectionState.reconnecting:
        return Container(
          width: double.infinity,
          color: cs.secondaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reconnecting…',
                  style: TextStyle(
                    color: cs.onSecondaryContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      case RoomConnectionState.failed:
        return Container(
          width: double.infinity,
          color: cs.errorContainer,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 16, color: cs.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Connection lost.',
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onErrorContainer,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        );
      case RoomConnectionState.connecting:
      case RoomConnectionState.connected:
      case RoomConnectionState.closed:
        return const SizedBox.shrink();
    }
  }
}

/// "X is typing…" strip rendered just above the composer.
class _TypingStrip extends StatelessWidget {
  const _TypingStrip({required this.typingUsers, required this.room});

  final List<String> typingUsers;
  final Room? room;

  String _label() {
    final names = typingUsers.map(_displayName).toList();
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names[0]} is typing…';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
    return 'Several people are typing…';
  }

  String _displayName(String userId) {
    final members = room?.members ?? const [];
    for (final m in members) {
      if (m.userId == userId) return m.displayName;
    }
    return userId.contains('@') ? userId.split('@').first : userId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = _label();
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.bottomCenter,
      child: label.isEmpty
          ? const SizedBox(width: double.infinity)
          : ReadingColumn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.room});
  final Room? room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 64,
              color: cs.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome to ${room?.name ?? 'this room'}',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Type a message to get started. Use @AgentName to call an '
              'agent, or @all to mention everyone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: cs.onErrorContainer),
            tooltip: 'Retry',
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _MembersAgentsPanel extends StatelessWidget {
  const _MembersAgentsPanel();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoomProvider>();
    final room = provider.currentRoom;
    if (room == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      shrinkWrap: true,
      children: [
        Text('Members', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final m in room.members)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: provider.onlineUsers.contains(m.userId)
                  ? Colors.green
                  : Colors.grey,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
            title: Text(m.displayName),
            subtitle: Text(_memberSubtitle(m)),
            trailing: m.role == 'owner'
                ? null
                : IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove member',
                    onPressed: () => _confirmRemoveMember(context, provider, m),
                  ),
          ),
        TextButton.icon(
          onPressed: () => _showInviteDialog(context, provider),
          icon: const Icon(Icons.person_add),
          label: const Text('Invite member'),
        ),
        const Divider(height: 32),
        Text('Agents', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final a in room.agents)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.tertiaryContainer,
              foregroundColor: theme.colorScheme.onTertiaryContainer,
              child: a.avatar != null && a.avatar!.isNotEmpty
                  ? Text(a.avatar!, style: const TextStyle(fontSize: 18))
                  : const Icon(Icons.smart_toy, size: 18),
            ),
            title: Text(a.name),
            subtitle: Text(_agentSubtitle(a)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove agent',
              onPressed: () => _confirmDeleteAgent(context, provider, a),
            ),
          ),
        TextButton.icon(
          onPressed: () => showAddAgentDialog(context, provider),
          icon: const Icon(Icons.smart_toy_outlined),
          label: const Text('Add agent'),
        ),
      ],
    );
  }

  /// Subtitle for a member row: show the email (when the title is a real name)
  /// alongside the role; degrade to just the role when there's no name to
  /// distinguish it from the email already shown in the title.
  String _memberSubtitle(RoomMember m) {
    final hasName = m.fullName != null && m.fullName!.trim().isNotEmpty;
    return hasName ? '${m.userId} · ${m.role}' : m.role;
  }

  String _agentSubtitle(RoomAgent a) {
    final parts = <String>[a.model, _modeLabel(a.responseMode)];
    if (a.isModerator) parts.add('moderator');
    return parts.join(' · ');
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'mention':
        return 'on @mention';
      case 'always':
        return 'always replies';
      case 'round_robin':
        return 'round-robin';
      case 'auto':
        return 'auto (smart)';
      default:
        return mode;
    }
  }

  Future<void> _confirmRemoveMember(
    BuildContext context,
    RoomProvider provider,
    RoomMember member,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${member.userId} from this room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await provider.removeMember(member.userId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove member: $e')));
      }
    }
  }

  Future<void> _confirmDeleteAgent(
    BuildContext context,
    RoomProvider provider,
    RoomAgent agent,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete agent?'),
        content: Text('Delete agent ${agent.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await provider.deleteAgent(agent.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete agent: $e')));
      }
    }
  }

  Future<void> _showInviteDialog(
    BuildContext context,
    RoomProvider provider,
  ) async {
    final emailCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite member'),
        content: TextField(
          controller: emailCtrl,
          decoration: const InputDecoration(labelText: 'Email'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              try {
                await provider.addMember(email);
                if (ctx.mounted) Navigator.of(ctx).pop();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              }
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }
}
