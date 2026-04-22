import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';

/// Full-page chat UI for a single multi-person / multi-agent room.
class RoomChatPage extends StatelessWidget {
  const RoomChatPage({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RoomProvider()..openRoom(roomId),
      child: const _RoomChatPageBody(),
    );
  }
}

class _RoomChatPageBody extends StatefulWidget {
  const _RoomChatPageBody();
  @override
  State<_RoomChatPageBody> createState() => _RoomChatPageBodyState();
}

class _RoomChatPageBodyState extends State<_RoomChatPageBody> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoomProvider>();
    final room = provider.currentRoom;
    _autoScroll();

    return Scaffold(
      appBar: AppBar(
        title: Text(room?.name ?? 'Loading...'),
        actions: [
          IconButton(
            tooltip: 'Members & agents',
            icon: const Icon(Icons.people),
            onPressed: () => _showPanel(context),
          ),
        ],
      ),
      body: provider.loading && room == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (provider.error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.red.withOpacity(0.1),
                    child: Text('Error: ${provider.error}'),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: provider.messages.length,
                    itemBuilder: (_, i) {
                      return _MessageBubble(
                        message: provider.messages[i],
                        room: room,
                      );
                    },
                  ),
                ),
                _ComposeBar(
                  controller: _controller,
                  onSend: (text) {
                    if (text.trim().isEmpty) return;
                    provider.sendMessage(text.trim());
                    _controller.clear();
                  },
                ),
              ],
            ),
    );
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.room});
  final RoomMessage message;
  final Room? room;

  String _authorLabel() {
    if (message.senderUserId != null) return message.senderUserId!;
    if (message.senderAgentId != null) {
      final agent =
          room?.agents.where((a) => a.id == message.senderAgentId).firstOrNull;
      final metaName = (message.meta?['agent_name'] as String?) ?? 'agent';
      return '🤖 ${agent?.name ?? metaName}';
    }
    return message.role;
  }

  @override
  Widget build(BuildContext context) {
    final isAgent = message.senderAgentId != null;
    return Align(
      alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: isAgent
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _authorLabel(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              message.content.isEmpty ? '…' : message.content,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeBar extends StatelessWidget {
  const _ComposeBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Message @AgentName, @all, or just chat…',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: onSend,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => onSend(controller.text),
              icon: const Icon(Icons.send),
              label: const Text('Send'),
            ),
          ],
        ),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        Text('Members', style: Theme.of(context).textTheme.titleMedium),
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
        Text('Agents', style: Theme.of(context).textTheme.titleMedium),
        for (final a in room.agents)
          ListTile(
            leading: Text(a.avatar ?? '🤖',
                style: const TextStyle(fontSize: 24)),
            title: Text('${a.name} (${a.model})'),
            subtitle: Text('${a.responseMode}${a.isModerator ? " · moderator" : ""}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => provider.deleteAgent(a.id),
            ),
          ),
        TextButton.icon(
          onPressed: () => _showAddAgentDialog(context, provider),
          icon: const Icon(Icons.smart_toy_outlined),
          label: const Text('Add agent'),
        ),
        const SizedBox(height: 24),
      ],
    );
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

  Future<void> _showAddAgentDialog(
      BuildContext context, RoomProvider provider) async {
    final nameCtrl = TextEditingController();
    final modelCtrl = TextEditingController(text: 'llama3.2');
    final promptCtrl = TextEditingController();
    String mode = 'mention';
    bool moderator = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add agent'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Agent name'),
                  autofocus: true,
                ),
                TextField(
                  controller: modelCtrl,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                TextField(
                  controller: promptCtrl,
                  decoration: const InputDecoration(
                      labelText: 'System prompt (optional)'),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration:
                      const InputDecoration(labelText: 'Response mode'),
                  items: const [
                    DropdownMenuItem(value: 'mention', child: Text('On @mention')),
                    DropdownMenuItem(value: 'always', child: Text('Always respond')),
                    DropdownMenuItem(value: 'round_robin', child: Text('Round-robin')),
                  ],
                  onChanged: (v) => setState(() => mode = v ?? 'mention'),
                ),
                SwitchListTile(
                  title: const Text('Moderator'),
                  value: moderator,
                  onChanged: (v) => setState(() => moderator = v),
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
                if (nameCtrl.text.trim().isEmpty ||
                    modelCtrl.text.trim().isEmpty) {
                  return;
                }
                try {
                  await provider.addAgent(
                    name: nameCtrl.text.trim(),
                    model: modelCtrl.text.trim(),
                    systemPrompt: promptCtrl.text.trim().isEmpty
                        ? null
                        : promptCtrl.text.trim(),
                    responseMode: mode,
                    isModerator: moderator,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

extension _ListFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
