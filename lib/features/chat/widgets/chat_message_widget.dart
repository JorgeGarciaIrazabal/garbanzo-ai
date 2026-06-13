import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../settings/providers/settings_provider.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import 'message/attachment_display.dart';
import 'message/branch_button.dart';
import 'message/copy_button.dart';
import 'message/edit_button.dart';
import 'message/message_content.dart';
import 'message/message_metadata.dart';
import 'message/regenerate_button.dart';
import 'message/speak_button.dart';
import 'message/thinking_content.dart';
import 'remember_this_button.dart';
import 'tool_bubble_widget.dart';

/// Widget for displaying a single chat message.
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

  /// Distinct knowledge-base filenames that informed this reply, stamped by
  /// the backend into the message metadata.
  List<String> get _kbSources {
    final raw = widget.message.metadata?['kb_sources'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsProvider>();

    // Tool invocations and results render as their own collapsible bubbles.
    if (widget.message.isToolCall || widget.message.isToolResult) {
      return ToolBubbleWidget(
        message: widget.message,
        isStreaming: widget.isStreaming,
      );
    }

    final isUser = widget.message.isUser;
    final thinkingContent = _extractThinkingContent();
    final isThinking = widget.isStreaming && thinkingContent != null && widget.message.content.isEmpty;
    final hasMetadata = _hasMetadata();

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.only(
            top: 4,
            bottom: 4,
            left: isUser ? 0 : MediaQuery.of(context).size.width * 0.01,
            right: isUser ? MediaQuery.of(context).size.width * 0.01 : 0,
          ),
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message header with role indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUser ? Icons.person : Icons.smart_toy,
                      size: 16,
                      color: isUser
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isUser ? 'You' : 'Assistant',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isUser
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.isStreaming || isThinking) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isUser
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isThinking ? 'Thinking...' : 'Generating...',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isUser
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    // Personal context transparency: show when stored
                    // memories informed this reply, so the user can tell
                    // what the AI knew without digging into the Info panel.
                    if (!isUser &&
                        (widget.message.metadata?['memories_used'] ?? 0) >
                            0) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message:
                            '${widget.message.metadata!['memories_used']} '
                            'saved memories about you informed this reply',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.psychology_outlined,
                              size: 12,
                              color: colorScheme.primary
                                  .withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.message.metadata!['memories_used']}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // The user stopped this response mid-generation; mark it
                    // so an interrupted answer isn't mistaken for a complete
                    // one.
                    if (!widget.isStreaming &&
                        widget.message.metadata?['stopped'] == true) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.stop_circle_outlined,
                        size: 12,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Stopped',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Attachments (images + document chips) for user messages
                if (isUser && widget.message.attachments.isNotEmpty)
                  AttachmentDisplay(
                    attachments: widget.message.attachments,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                  ),
                // Thinking content (expandable). Auto-expanded while the
                // model is still mid-stream so the user sees reasoning
                // tokens scroll by in real time, then collapses once the
                // final answer starts arriving.
                if (thinkingContent != null && !isUser)
                  ThinkingContent(
                    thinkingContent: thinkingContent,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                    isLive: widget.isStreaming &&
                        widget.message.content.isEmpty,
                    hasContent: widget.message.content.isNotEmpty,
                  ),
                // Message content
                if (widget.message.content.isNotEmpty)
                  MessageContent(
                    content: widget.message.content,
                    isUser: isUser,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                  ),
                // Knowledge-base citations: which documents informed this
                // reply.
                if (!isUser && _kbSources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final source in _kbSources)
                          Tooltip(
                            message: 'From your knowledge base',
                            child: Chip(
                              avatar: Icon(
                                Icons.menu_book_outlined,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              label: Text(source),
                              labelStyle: theme.textTheme.labelSmall,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                              backgroundColor:
                                  colorScheme.surfaceContainerLow,
                            ),
                          ),
                      ],
                    ),
                  ),
                // Action buttons for assistant messages
                if (!isUser && widget.message.content.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (settings.showMessageMetadata && hasMetadata)
                          MetadataIconToggle(
                            isExpanded: _metadataExpanded,
                            onToggle: () => setState(() => _metadataExpanded = !_metadataExpanded),
                            colorScheme: colorScheme,
                          ),
                        if (settings.showMessageMetadata && hasMetadata)
                          const SizedBox(width: 8),
                        CopyButton(content: widget.message.content),
                        const SizedBox(width: 8),
                        SpeakButton(
                          content: widget.message.content,
                          isStreaming: widget.isStreaming,
                        ),
                        if (widget.isLastAssistant &&
                            !widget.isStreaming &&
                            !widget.message.id.startsWith('temp-')) ...[
                          const SizedBox(width: 8),
                          Builder(builder: (ctx) {
                            final chat = ctx.watch<ChatProvider>();
                            return RegenerateButton(
                              enabled: !chat.isSending,
                              onPressed: () => chat.regenerateLastAssistant(),
                            );
                          }),
                        ],
                        if (!widget.isStreaming && !widget.message.id.startsWith('temp-')) ...[
                          const SizedBox(width: 8),
                          Builder(builder: (ctx) {
                            final chat = ctx.watch<ChatProvider>();
                            return BranchButton(
                              enabled: !chat.isSending,
                              onPressed: () => chat.branchFromMessage(widget.message.id),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                  // Expanded metadata details (appears below the row when toggled)
                  if (_metadataExpanded && hasMetadata)
                    MetadataDetails(
                      metadata: widget.message.metadata!,
                      colorScheme: colorScheme,
                      textTheme: theme.textTheme,
                    ),
                ],
                // Action buttons for user messages
                if (isUser && widget.message.content.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CopyButton(content: widget.message.content),
                        const SizedBox(width: 8),
                        if (!widget.message.id.startsWith('temp-'))
                          Builder(builder: (ctx) {
                            final chat = ctx.watch<ChatProvider>();
                            return EditMessageButton(
                              content: widget.message.content,
                              enabled: !chat.isSending,
                              onSubmit: (newContent) => chat.editUserMessage(
                                widget.message.id,
                                newContent,
                              ),
                            );
                          }),
                        const SizedBox(width: 8),
                        RememberThisButton(
                          content: widget.message.content,
                          sourceConversationId: widget.conversationId,
                        ),
                        if (!widget.message.id.startsWith('temp-')) ...[
                          const SizedBox(width: 8),
                          Builder(builder: (ctx) {
                            final chat = ctx.watch<ChatProvider>();
                            return BranchButton(
                              enabled: !chat.isSending,
                              onPressed: () => chat.branchFromMessage(widget.message.id),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
