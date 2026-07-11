import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/widgets/markdown_widget.dart';

/// Displays message content with markdown rendering.
class MessageContent extends StatelessWidget {
  const MessageContent({
    super.key,
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
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }
    return MarkdownWidget(
      content: content,
      colorScheme: colorScheme,
      textTheme: textTheme,
      isSelectable: true,
    );
  }
}
