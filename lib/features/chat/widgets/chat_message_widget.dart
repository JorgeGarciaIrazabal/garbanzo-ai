import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/action_proposal_card.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/pulsing_dot.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/attachment_display.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/branch_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/copy_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/edit_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_content.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_metadata.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/regenerate_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/reveal_on_hover.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/speak_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/thinking_content.dart';
import 'package:garbanzo_ai/features/chat/widgets/remember_this_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Widget for displaying a single chat message.
///
/// Assistant replies render as flat prose on the canvas — no card, no header —
/// so markdown-heavy answers read like a document. User messages render as
/// compact right-aligned bubbles. Action rows sit below the content and stay
/// dim until hovered (the latest assistant reply keeps its actions visible).
class ChatMessageWidget extends StatefulWidget {
  const ChatMessageWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.conversationId,
    this.isLastAssistant = false,
  });

  final ChatMessage message;
  final bool isStreaming;
  final String? conversationId;

  /// Whether this is the most recent assistant message in the thread.
  /// Used to show the "Regenerate" button only on the latest reply.
  final bool isLastAssistant;

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  bool _metadataExpanded = false;
  bool _hovered = false;

  /// Distinct knowledge-base filenames that informed this reply, stamped by
  /// the backend into the message metadata.
  List<String> get _kbSources {
    final raw = widget.message.metadata?['kb_sources'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  @override
  Widget build(BuildContext context) {
    // A proposal tool's result renders as a Confirm/Cancel card — the user
    // decides whether the proposed action (create room, change style) runs.
    if (widget.message.isToolResult && widget.message.actionProposal != null) {
      return ActionProposalCard(message: widget.message);
    }

    // Tool invocations and results render as their own collapsible bubbles.
    if (widget.message.isToolCall || widget.message.isToolResult) {
      return ToolBubbleWidget(
        message: widget.message,
        isStreaming: widget.isStreaming,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.message.isUser
          ? _buildUserTurn(context)
          : _buildAssistantTurn(context),
    );
  }

  // -- User turn --------------------------------------------------------------

  Widget _buildUserTurn(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final message = widget.message;

    final bubbleColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.14 : 0.08),
      colorScheme.surfaceContainerHigh,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.attachments.isNotEmpty)
                      AttachmentDisplay(
                        attachments: message.attachments,
                        colorScheme: colorScheme,
                        textTheme: theme.textTheme,
                      ),
                    if (message.content.isNotEmpty)
                      MessageContent(
                        content: message.content,
                        isUser: true,
                        colorScheme: colorScheme,
                        textTheme: theme.textTheme,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (message.content.isNotEmpty)
            RevealOnHover(
              revealed: _hovered,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CopyButton(content: message.content),
                    const SizedBox(width: 8),
                    if (!message.id.startsWith('temp-'))
                      Builder(
                        builder: (ctx) {
                          final chat = ctx.watch<ChatProvider>();
                          return EditMessageButton(
                            content: message.content,
                            enabled: !chat.isSending,
                            onSubmit: (newContent) =>
                                chat.editUserMessage(message.id, newContent),
                          );
                        },
                      ),
                    const SizedBox(width: 8),
                    RememberThisButton(
                      content: message.content,
                      sourceConversationId: widget.conversationId,
                    ),
                    if (!message.id.startsWith('temp-')) ...[
                      const SizedBox(width: 8),
                      Builder(
                        builder: (ctx) {
                          final chat = ctx.watch<ChatProvider>();
                          return BranchButton(
                            enabled: !chat.isSending,
                            onPressed: () => chat.branchFromMessage(message.id),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -- Assistant turn ---------------------------------------------------------

  Widget _buildAssistantTurn(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsProvider>();
    final message = widget.message;

    final thinkingContent = _extractThinkingContent();
    final hasMetadata = _hasMetadata();

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thinking content (expandable). Auto-expanded while the model is
          // still mid-stream so the user sees reasoning tokens scroll by in
          // Collapsed by default; the user taps to reveal the reasoning.
          if (thinkingContent != null)
            ThinkingContent(
              thinkingContent: thinkingContent,
              colorScheme: colorScheme,
              textTheme: theme.textTheme,
              isLive: widget.isStreaming && message.content.isEmpty,
            ),
          if (message.content.isNotEmpty)
            MessageContent(
              content: message.content,
              isUser: false,
              colorScheme: colorScheme,
              textTheme: theme.textTheme,
            ),
          // Knowledge-base citations: which documents informed this reply.
          if (_kbSources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final source in _kbSources)
                    Tooltip(
                      message: AppLocalizations.of(
                        context,
                      )!.fromYourKnowledgeBase,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 12,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              source,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // While streaming, a single pulsing dot occupies the slot the
          // action row takes over once the reply settles — no layout jump.
          if (widget.isStreaming)
            Padding(
              padding: EdgeInsets.only(
                top: message.content.isEmpty ? 4 : 10,
                left: 2,
              ),
              child: PulsingDot(color: colorScheme.primary),
            )
          else if (message.content.isNotEmpty) ...[
            RevealOnHover(
              revealed: _hovered || widget.isLastAssistant,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CopyButton(content: message.content),
                    const SizedBox(width: 8),
                    SpeakButton(
                      content: message.content,
                      isStreaming: widget.isStreaming,
                    ),
                    if (widget.isLastAssistant &&
                        !message.id.startsWith('temp-')) ...[
                      const SizedBox(width: 8),
                      Builder(
                        builder: (ctx) {
                          final chat = ctx.watch<ChatProvider>();
                          return RegenerateButton(
                            enabled: !chat.isSending,
                            onPressed: () => chat.regenerateLastAssistant(),
                          );
                        },
                      ),
                    ],
                    if (!message.id.startsWith('temp-')) ...[
                      const SizedBox(width: 8),
                      Builder(
                        builder: (ctx) {
                          final chat = ctx.watch<ChatProvider>();
                          return BranchButton(
                            enabled: !chat.isSending,
                            onPressed: () => chat.branchFromMessage(message.id),
                          );
                        },
                      ),
                    ],
                    if (settings.showMessageMetadata && hasMetadata) ...[
                      const SizedBox(width: 8),
                      MetadataIconToggle(
                        isExpanded: _metadataExpanded,
                        onToggle: () => setState(
                          () => _metadataExpanded = !_metadataExpanded,
                        ),
                        colorScheme: colorScheme,
                      ),
                    ],
                    ..._buildQuietIndicators(theme, colorScheme),
                  ],
                ),
              ),
            ),
            if (_metadataExpanded && hasMetadata)
              MetadataDetails(
                metadata: message.metadata!,
                colorScheme: colorScheme,
                textTheme: theme.textTheme,
              ),
          ],
        ],
      ),
    );
  }

  /// Small trailing indicators on the action row: memories that informed the
  /// reply, and whether the user stopped generation early.
  List<Widget> _buildQuietIndicators(ThemeData theme, ColorScheme colorScheme) {
    final indicators = <Widget>[];
    final memoriesUsed = widget.message.metadata?['memories_used'];
    if (memoriesUsed is num && memoriesUsed > 0) {
      indicators.addAll([
        const SizedBox(width: 12),
        Tooltip(
          message: '$memoriesUsed saved memories about you informed this reply',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 13,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 3),
              Text(
                '$memoriesUsed',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ]);
    }
    // The user stopped this response mid-generation; mark it so an
    // interrupted answer isn't mistaken for a complete one.
    if (widget.message.metadata?['stopped'] == true) {
      indicators.addAll([
        const SizedBox(width: 12),
        Icon(
          Icons.stop_circle_outlined,
          size: 13,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 3),
        Text(
          'Stopped',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
        ),
      ]);
    }
    return indicators;
  }

  String? _extractThinkingContent() {
    final metadata = widget.message.metadata;
    if (metadata == null) return null;
    final thinking = metadata['thinking'];
    if (thinking is String && thinking.isNotEmpty) {
      return thinking;
    }
    return null;
  }

  bool _hasMetadata() {
    final metadata = widget.message.metadata;
    if (metadata == null) return false;
    return metadata.containsKey('tokens_prompt') ||
        metadata.containsKey('input_tokens') ||
        metadata.containsKey('tokens_generated') ||
        metadata.containsKey('output_tokens') ||
        metadata.containsKey('total_duration_ns') ||
        metadata.containsKey('response_time_ms');
  }
}
