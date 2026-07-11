import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/reading_column.dart';
import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
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
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoomProvider>();
    final room = provider.currentRoom;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final me = AuthService.instance.cachedUser?.email;
    final messages = provider.messages;
    _autoScroll();

    final lastMsg = messages.isEmpty ? null : messages.last;
    final lastIsStreamingAgent = lastMsg != null &&
        lastMsg.senderAgentId != null;

    final showSidebar = context.isWide;

    final mainColumn = provider.loading && room == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (provider.error != null)
                _ErrorBanner(
                  message: provider.error!,
                  onDismiss: () =>
                      room != null ? provider.openRoom(room.id) : null,
                ),
              Expanded(
                child: messages.isEmpty
                    ? _EmptyState(room: room)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final m = messages[i];
                          final isLast = i == messages.length - 1;
                          return ReadingColumn(
                            child: RoomMessageBubble(
                              message: m,
                              room: room,
                              currentUserEmail: me,
                              isStreaming: isLast &&
                                  lastIsStreamingAgent &&
                                  // Streaming placeholders have empty
                                  // content until done; we treat the last
                                  // agent message as streaming only if it's
                                  // still empty (the provider replaces with
                                  // the canonical message when done).
                                  m.content.isEmpty,
                            ),
                          );
                        },
                      ),
              ),
              MessageComposer(
                enabled: room != null,
                hintText: 'Message the room… (use @AgentName or @all)',
                onSend: (text) => provider.sendMessage(text),
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
            Icon(Icons.forum_outlined,
                size: 64, color: cs.primary.withOpacity(0.5)),
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
            title: Text(m.userId),
            subtitle: Text(m.role),
            trailing: m.role == 'owner'
                ? null
                : IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => provider.removeMember(m.userId),
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
              onPressed: () => provider.deleteAgent(a.id),
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

  Future<void> _showInviteDialog(
      BuildContext context, RoomProvider provider) async {
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
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
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
