import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/reading_column.dart';
import 'package:garbanzo_ai/core/smart_scroll_controller.dart';
import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/fade_slide_in.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/core/widgets/user_avatar.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attach_menu_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attachment_preview.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';
import 'package:garbanzo_ai/features/rooms/widgets/add_agent_dialog.dart';
import 'package:garbanzo_ai/features/rooms/widgets/mute_room_sheet.dart';
import 'package:garbanzo_ai/features/rooms/widgets/room_message_bubble.dart';

/// Room chat rendered inside the main chat shell's content pane — the shell
/// keeps its sidebar, so switching between chats and rooms never leaves the
/// page.
///
/// Reads the app-level [RoomProvider]; opens the room's socket on mount,
/// follows [roomId] changes, and closes the socket when disposed (unless a
/// newer view has already taken the connection over).
class RoomChatView extends StatefulWidget {
  const RoomChatView({
    super.key,
    required this.roomId,
    required this.onOpenSettings,
    this.onOpenDrawer,
  });

  final String roomId;

  /// Opens the settings end-drawer (owned by the shell's Scaffold).
  final VoidCallback onOpenSettings;

  /// Narrow layouts only: opens the chats/rooms drawer.
  final VoidCallback? onOpenDrawer;

  @override
  State<RoomChatView> createState() => _RoomChatViewState();
}

class _RoomChatViewState extends State<RoomChatView>
    with WidgetsBindingObserver {
  final _scroll = SmartScrollController();
  final List<ChatAttachment> _attachments = [];
  RoomProvider? _providerRef;

  /// Monotonic mount counter: a disposed view must never close a socket a
  /// newer view (re)opened. Only one RoomChatView exists at a time.
  static int _mountCounter = 0;
  late final int _mountId;

  @override
  void initState() {
    super.initState();
    _mountId = ++_mountCounter;
    _scroll.attach();
    WidgetsBinding.instance.addObserver(this);
    // openRoom notifies listeners, so it can't run synchronously here (we're
    // mid-build and the sidebar watches the same provider).
    final provider = context.read<RoomProvider>();
    if (provider.currentRoom?.id != widget.roomId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) provider.openRoom(widget.roomId);
      });
    }
  }

  @override
  void didUpdateWidget(covariant RoomChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      final provider = context.read<RoomProvider>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) provider.openRoom(widget.roomId);
      });
    }
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
  void didChangeMetrics() {
    // Keep the newest messages visible while the on-screen keyboard opens.
    _scroll.handleKeyboardInset(View.of(context).viewInsets.bottom);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _providerRef?.streamingMessage.removeListener(_onStreamingUpdate);
    _scroll.dispose();
    final provider = _providerRef;
    final roomId = widget.roomId;
    // Deferred so leaveRoom's notifyListeners can't fire mid-teardown, and
    // guarded so a swap to another room (whose openRoom is in flight) or a
    // newer mount never gets its socket closed from under it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mountCounter == _mountId && provider?.currentRoom?.id == roomId) {
        provider?.leaveRoom();
      }
    });
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

    final body = room == null && provider.error == null
        ? const SkeletonList(showAvatar: true, itemCount: 6)
        : Column(
            children: [
              if (provider.error != null)
                _ErrorBanner(
                  message: provider.error!,
                  onDismiss: () => provider.openRoom(widget.roomId),
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
                onSend: (text) {
                  provider.sendMessage(
                    text,
                    attachments: List.of(_attachments),
                  );
                  setState(() => _attachments.clear());
                },
                onChanged: provider.handleComposerChanged,
                onBlur: provider.handleComposerBlur,
                hasExtraContent: _attachments.isNotEmpty,
                above: _attachments.isEmpty
                    ? null
                    : AttachmentPreviewBar(
                        attachments: _attachments,
                        onRemove: (i) =>
                            setState(() => _attachments.removeAt(i)),
                        colorScheme: colorScheme,
                        textTheme: theme.textTheme,
                      ),
                leading: AttachMenuButton(
                  buttonKey: const ValueKey('room_attach_button'),
                  enabled: room != null,
                  existingNames: () => _attachments.map((a) => a.name).toSet(),
                  onAdded: (added) =>
                      setState(() => _attachments.addAll(added)),
                ),
              ),
            ],
          );

    return Column(
      children: [
        AppBar(
          automaticallyImplyLeading: false,
          leading: widget.onOpenDrawer == null
              ? null
              : IconButton(
                  tooltip: 'Open chats and rooms',
                  icon: const Icon(Icons.menu),
                  onPressed: widget.onOpenDrawer,
                ),
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
            Builder(
              builder: (buttonContext) {
                final muted = room?.isMuted ?? false;
                return IconButton(
                  key: const ValueKey('room_mute_button'),
                  tooltip: muted
                      ? muteStatusLabel(room?.mutedUntil)
                      : 'Mute notifications',
                  icon: Icon(
                    muted
                        ? Icons.notifications_off
                        : Icons.notifications_none_outlined,
                  ),
                  onPressed: room == null
                      ? null
                      : () => _showMuteSheet(buttonContext, provider, room),
                );
              },
            ),
            IconButton(
              tooltip: 'Members & agents',
              icon: const Icon(Icons.group_outlined),
              onPressed: room == null ? null : () => _showPanel(context),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: widget.onOpenSettings,
            ),
            const SizedBox(width: 8),
          ],
        ),
        Expanded(child: body),
      ],
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
            FadeSlideIn(
              child: ReadingColumn(
                child: RoomMessageBubble(
                  message: msg,
                  room: room,
                  currentUserEmail: me,
                  isStreaming: isStreaming,
                ),
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

  String _subtitleForRoom(Room room, int onlineCount) {
    final memberWord = room.memberCount == 1 ? 'member' : 'members';
    final agentWord = room.agentCount == 1 ? 'agent' : 'agents';
    final base =
        '${room.memberCount} $memberWord · ${room.agentCount} $agentWord';
    if (onlineCount > 0) return '$base · $onlineCount online';
    return base;
  }

  Future<void> _showMuteSheet(
    BuildContext context,
    RoomProvider provider,
    Room room,
  ) async {
    final duration = await showMuteRoomSheet(
      context: context,
      roomName: room.name,
      mutedUntil: room.mutedUntil,
    );
    if (duration != null) await provider.setMute(room.id, duration);
  }

  void _showPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _MembersAgentsPanel(),
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
            leading: UserAvatar(
              profilePictureB64: m.profilePictureB64,
              displayName: m.displayName,
              backgroundColor: provider.onlineUsers.contains(m.userId)
                  ? Colors.green
                  : Colors.grey,
              foregroundColor: Colors.white,
              radius: 20,
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
    final ok = await showAnimatedDialog<bool>(
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
    final ok = await showAnimatedDialog<bool>(
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
    await showAnimatedDialog(
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
