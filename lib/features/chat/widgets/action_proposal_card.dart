import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';

/// Confirm/Cancel card for an action proposal returned by a proposal tool
/// (create_room, set_conversation_style).
///
/// The LLM only ever *proposes*; nothing happens until the user confirms
/// here, and the confirm handler calls the same REST services the normal UI
/// uses — auth is reused and the model stays out of the execution path.
/// Decisions are keyed by the proposal's tool_call_id in SharedPreferences
/// so a confirmed card can't be re-confirmed after a reload (double-creating
/// the room).
class ActionProposalCard extends StatefulWidget {
  const ActionProposalCard({super.key, required this.message});

  final ChatMessage message;

  @override
  State<ActionProposalCard> createState() => _ActionProposalCardState();
}

enum _Decision { pending, working, confirmed, dismissed, failed }

class _ActionProposalCardState extends State<ActionProposalCard> {
  _Decision _decision = _Decision.pending;
  String? _resultNote;

  Map<String, dynamic> get _proposal =>
      widget.message.actionProposal ?? const {};
  String get _type => (_proposal['type'] as String?) ?? '';
  String get _summary => (_proposal['summary'] as String?) ?? 'Proposed action';
  Map<String, dynamic> get _payload {
    final p = _proposal['payload'];
    return p is Map ? Map<String, dynamic>.from(p) : const {};
  }

  String? get _decisionKey {
    final id = widget.message.toolCallId;
    return id == null ? null : 'action_proposal_decision_$id';
  }

  @override
  void initState() {
    super.initState();
    _loadDecision();
  }

  Future<void> _loadDecision() async {
    final key = _decisionKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key);
    if (!mounted || stored == null) return;
    setState(() {
      _decision = stored == 'confirmed'
          ? _Decision.confirmed
          : _Decision.dismissed;
    });
  }

  Future<void> _storeDecision(String value) async {
    final key = _decisionKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          key: const ValueKey('action_proposal_card'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icon, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_title, style: theme.textTheme.titleSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_summary, style: theme.textTheme.bodyMedium),
                ..._details(theme),
                const SizedBox(height: 12),
                _actions(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (_type) {
    'create_room' => Icons.forum_outlined,
    'set_conversation_style' => Icons.palette_outlined,
    _ => Icons.task_alt,
  };

  String get _title => switch (_type) {
    'create_room' => 'Create a room?',
    'set_conversation_style' => 'Change conversation style?',
    _ => 'Confirm action?',
  };

  List<Widget> _details(ThemeData theme) {
    final lines = <String>[];
    if (_type == 'create_room') {
      final members = (_payload['member_emails'] as List?) ?? const [];
      final agents = (_payload['agents'] as List?) ?? const [];
      if (members.isNotEmpty) lines.add('Members: ${members.join(', ')}');
      for (final a in agents.whereType<Map>()) {
        final mode = a['response_mode'] ?? 'mention';
        lines.add('Agent: ${a['name']} (${a['model']}, replies: $mode)');
      }
    }
    if (lines.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      for (final line in lines)
        Text(
          line,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    ];
  }

  Widget _actions(ColorScheme colorScheme) {
    switch (_decision) {
      case _Decision.working:
        return const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _Decision.confirmed:
        return _statusRow(
          Icons.check_circle_outline,
          _resultNote ?? 'Done',
          colorScheme.primary,
        );
      case _Decision.dismissed:
        return _statusRow(
          Icons.cancel_outlined,
          'Dismissed',
          colorScheme.onSurfaceVariant,
        );
      case _Decision.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusRow(
              Icons.error_outline,
              _resultNote ?? 'Failed',
              colorScheme.error,
            ),
            const SizedBox(height: 8),
            _buttons(),
          ],
        );
      case _Decision.pending:
        return _buttons();
    }
  }

  Widget _statusRow(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }

  Widget _buttons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          key: const ValueKey('action_proposal_confirm'),
          onPressed: _confirm,
          child: const Text('Confirm'),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const ValueKey('action_proposal_cancel'),
          onPressed: _dismiss,
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _dismiss() async {
    setState(() => _decision = _Decision.dismissed);
    await _storeDecision('dismissed');
  }

  Future<void> _confirm() async {
    setState(() => _decision = _Decision.working);
    try {
      final note = switch (_type) {
        'create_room' => await _executeCreateRoom(),
        'set_conversation_style' => await _executeSetStyle(),
        _ => throw Exception('Unknown proposal type: $_type'),
      };
      if (!mounted) return;
      setState(() {
        _decision = _Decision.confirmed;
        _resultNote = note;
      });
      await _storeDecision('confirmed');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _decision = _Decision.failed;
        _resultNote = 'Failed: $e';
      });
    }
  }

  Future<String> _executeCreateRoom() async {
    final service = RoomService.instance;
    final members = ((_payload['member_emails'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final room = await service.createRoom(
      name: (_payload['name'] as String?) ?? 'Room',
      description: _payload['description'] as String?,
      memberEmails: members,
    );
    final agents = ((_payload['agents'] as List?) ?? const []).whereType<Map>();
    for (final a in agents) {
      await service.addAgent(
        room.id,
        name: (a['name'] as String?) ?? 'Agent',
        model: (a['model'] as String?) ?? '',
        systemPrompt: a['system_prompt'] as String?,
        responseMode: (a['response_mode'] as String?) ?? 'mention',
        isModerator: (a['is_moderator'] as bool?) ?? false,
      );
    }
    return "Room '${room.name}' created";
  }

  Future<String> _executeSetStyle() async {
    final chat = context.read<ChatProvider>();
    final models = context.read<ModelProvider>();
    final model = _payload['model'] as String?;
    final thinkingRaw = _payload['thinking_level'] as String?;
    final systemPrompt = _payload['system_prompt'] as String?;

    if (chat.currentConversation == null) {
      throw Exception('No active conversation');
    }
    if (model != null && model.isNotEmpty) {
      models.selectModel(model);
    }
    await chat.updateConversation(
      model: (model != null && model.isNotEmpty) ? model : null,
      thinkingLevel: thinkingRaw == null
          ? null
          : ThinkingLevel.values.asNameMap()[thinkingRaw],
      setThinkingLevel: thinkingRaw != null,
      systemPrompt: systemPrompt,
    );
    return 'Conversation style updated';
  }
}
