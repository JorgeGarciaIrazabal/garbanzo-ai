import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';

/// Widget for displaying a single chat message.
class ChatMessageWidget extends StatelessWidget {
  const ChatMessageWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  final ChatMessage message;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                    if (isStreaming) ...[
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
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Message content
                _MessageContent(
                  content: message.content,
                  isUser: isUser,
                  colorScheme: colorScheme,
                  textTheme: theme.textTheme,
                ),
                // Copy button for assistant messages
                if (!isUser)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: _CopyButton(content: message.content),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays message content with basic formatting.
class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.content,
    required this.isUser,
    required this.colorScheme,
    required this.textTheme,
  });

  final String content;
  final bool isUser;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // Simple text display - in production, consider using a markdown package
    return SelectableText(
      content,
      style: textTheme.bodyMedium?.copyWith(
        color: isUser
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}

/// Copy button for copying message content.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.content});

  final String content;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: _copied
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withOpacity(0.6),
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied!' : 'Copy',
              style: TextStyle(
                fontSize: 12,
                color: _copied
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
