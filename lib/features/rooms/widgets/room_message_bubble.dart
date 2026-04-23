import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/widgets/markdown_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_metadata.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/thinking_content.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';

/// Bubble rendering for a single room message.
///
/// Three visual variants:
///   • Self  — right-aligned, primary container.
///   • Other person — left-aligned, secondary container, person icon.
///   • Agent — left-aligned, surfaceContainerHighest, smart_toy icon, model.
class RoomMessageBubble extends StatefulWidget {
  const RoomMessageBubble({
    super.key,
    required this.message,
    required this.room,
    required this.currentUserEmail,
    required this.isStreaming,
  });

  final RoomMessage message;
  final Room? room;
  final String? currentUserEmail;
  final bool isStreaming;

  @override
  State<RoomMessageBubble> createState() => _RoomMessageBubbleState();
}

class _RoomMessageBubbleState extends State<RoomMessageBubble> {
  bool _metadataExpanded = false;

  bool get _isAgent => widget.message.senderAgentId != null;
  bool get _isSelf =>
      widget.message.senderUserId != null &&
      widget.currentUserEmail != null &&
      widget.message.senderUserId == widget.currentUserEmail;

  RoomAgent? _agent() {
    final id = widget.message.senderAgentId;
    if (id == null || widget.room == null) return null;
    for (final a in widget.room!.agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  String? _thinkingContent() {
    final meta = widget.message.meta;
    if (meta == null) return null;
    final thinking = meta['thinking'];
    if (thinking is String && thinking.isNotEmpty) return thinking;
    return null;
  }

  bool _hasMetadata() {
    final meta = widget.message.meta;
    if (meta == null) return false;
    return meta.containsKey('tokens_prompt') ||
        meta.containsKey('input_tokens') ||
        meta.containsKey('tokens_generated') ||
        meta.containsKey('output_tokens') ||
        meta.containsKey('total_duration_ns') ||
        meta.containsKey('response_time_ms');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaWidth = MediaQuery.of(context).size.width;

    final variant = _resolveVariant(colorScheme);
    final thinking = _isAgent ? _thinkingContent() : null;
    final hasMeta = _isAgent && _hasMetadata();

    return Align(
      alignment: _isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: mediaWidth * 0.92),
        child: Padding(
          padding: EdgeInsets.only(
            top: 4,
            bottom: 4,
            left: _isSelf ? 0 : 4,
            right: _isSelf ? 4 : 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isSelf) ...[
                _Avatar(variant: variant),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: variant.bubbleColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(_isSelf ? 16 : 4),
                      bottomRight: Radius.circular(_isSelf ? 4 : 16),
                    ),
                    side: variant.outlineColor == null
                        ? BorderSide.none
                        : BorderSide(color: variant.outlineColor!, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(
                          variant: variant,
                          isStreaming: widget.isStreaming,
                          theme: theme,
                          createdAt: widget.message.createdAt,
                        ),
                        const SizedBox(height: 6),
                        if (thinking != null)
                          ThinkingContent(
                            thinkingContent: thinking,
                            colorScheme: colorScheme,
                            textTheme: theme.textTheme,
                          ),
                        if (widget.message.content.isEmpty && widget.isStreaming)
                          _TypingDots(color: variant.fgColor.withOpacity(0.6))
                        else if (_isAgent && widget.message.content.isNotEmpty)
                          MarkdownWidget(
                            content: widget.message.content,
                            colorScheme: colorScheme,
                            textTheme: theme.textTheme,
                          )
                        else
                          SelectableText(
                            widget.message.content.isEmpty
                                ? '…'
                                : widget.message.content,
                            style: TextStyle(color: variant.fgColor),
                          ),
                        if (hasMeta) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: MetadataIconToggle(
                              isExpanded: _metadataExpanded,
                              onToggle: () => setState(
                                () => _metadataExpanded = !_metadataExpanded,
                              ),
                              colorScheme: colorScheme,
                            ),
                          ),
                          if (_metadataExpanded)
                            MetadataDetails(
                              metadata: widget.message.meta!,
                              colorScheme: colorScheme,
                              textTheme: theme.textTheme,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_isSelf) ...[
                const SizedBox(width: 8),
                _Avatar(variant: variant),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _BubbleVariant _resolveVariant(ColorScheme cs) {
    if (_isSelf) {
      return _BubbleVariant(
        kind: _BubbleKind.self,
        title: 'You',
        avatarIcon: Icons.person,
        bubbleColor: cs.primaryContainer,
        fgColor: cs.onPrimaryContainer,
        avatarBg: cs.primary,
        avatarFg: cs.onPrimary,
        outlineColor: null,
      );
    }
    if (_isAgent) {
      final a = _agent();
      final name =
          a?.name ?? (widget.message.meta?['agent_name'] as String?) ?? 'Agent';
      final modelLabel = a?.model;
      return _BubbleVariant(
        kind: _BubbleKind.agent,
        title: name,
        subtitle: modelLabel,
        avatarText: a?.avatar,
        avatarIcon: Icons.smart_toy,
        bubbleColor: cs.surfaceContainerHighest,
        fgColor: cs.onSurface,
        avatarBg: cs.tertiaryContainer,
        avatarFg: cs.onTertiaryContainer,
        outlineColor: cs.outlineVariant.withOpacity(0.4),
      );
    }
    final email = widget.message.senderUserId ?? 'user';
    final localPart = email.contains('@') ? email.split('@').first : email;
    return _BubbleVariant(
      kind: _BubbleKind.other,
      title: localPart,
      subtitle: email,
      avatarLetter:
          localPart.isEmpty ? '?' : localPart.characters.first.toUpperCase(),
      avatarIcon: Icons.person,
      bubbleColor: cs.secondaryContainer,
      fgColor: cs.onSecondaryContainer,
      avatarBg: cs.secondary,
      avatarFg: cs.onSecondary,
      outlineColor: null,
    );
  }
}

enum _BubbleKind { self, other, agent }

class _BubbleVariant {
  _BubbleVariant({
    required this.kind,
    required this.title,
    this.subtitle,
    this.avatarLetter,
    this.avatarText,
    required this.avatarIcon,
    required this.bubbleColor,
    required this.fgColor,
    required this.avatarBg,
    required this.avatarFg,
    required this.outlineColor,
  });

  final _BubbleKind kind;
  final String title;
  final String? subtitle;
  final String? avatarLetter;
  final String? avatarText;
  final IconData avatarIcon;
  final Color bubbleColor;
  final Color fgColor;
  final Color avatarBg;
  final Color avatarFg;
  final Color? outlineColor;
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.variant});

  final _BubbleVariant variant;

  @override
  Widget build(BuildContext context) {
    final hasGlyph = variant.avatarText != null && variant.avatarText!.isNotEmpty;
    final hasLetter = variant.avatarLetter != null;
    return CircleAvatar(
      radius: 16,
      backgroundColor: variant.avatarBg,
      foregroundColor: variant.avatarFg,
      child: hasGlyph
          ? Text(variant.avatarText!, style: const TextStyle(fontSize: 16))
          : hasLetter
              ? Text(
                  variant.avatarLetter!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Icon(variant.avatarIcon, size: 18),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.variant,
    required this.isStreaming,
    required this.theme,
    required this.createdAt,
  });

  final _BubbleVariant variant;
  final bool isStreaming;
  final ThemeData theme;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final fgMuted = variant.fgColor.withOpacity(0.7);
    return Row(
      children: [
        Flexible(
          child: Text(
            variant.title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: variant.fgColor,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (variant.subtitle != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '· ${variant.subtitle}',
              style: theme.textTheme.labelSmall?.copyWith(color: fgMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(width: 8),
        Text(
          _formatTime(createdAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: fgMuted,
            fontSize: 11,
          ),
        ),
        if (isStreaming) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: variant.fgColor.withOpacity(0.7),
            ),
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (t + i * 0.2) % 1.0;
            final scale = 0.7 + 0.6 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
