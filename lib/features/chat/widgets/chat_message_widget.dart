import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../settings/providers/settings_provider.dart';
import '../models/chat_message.dart';
import 'message/attachment_display.dart';
import 'message/copy_button.dart';
import 'message/message_content.dart';
import 'message/message_metadata.dart';
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
  });

  final ChatMessage message;
  final bool isStreaming;
  final String? conversationId;

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  bool _metadataExpanded = false;

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
                // Thinking content (expandable)
                if (thinkingContent != null && !isUser)
                  ThinkingContent(
                    thinkingContent: thinkingContent,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                  ),
                // Message content
                if (widget.message.content.isNotEmpty)
                  MessageContent(
                    content: widget.message.content,
                    isUser: isUser,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
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
                        RememberThisButton(
                          content: widget.message.content,
                          sourceConversationId: widget.conversationId,
                        ),
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
