import 'package:flutter/material.dart';

/// Shown when no conversation is active — prompts the user to start chatting.
class EmptyChatState extends StatelessWidget {
  const EmptyChatState({super.key, required this.onSendMessage});

  final ValueChanged<String> onSendMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'Start a conversation',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Type a message below to begin chatting',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _SuggestionChip(
                text: 'Explain quantum computing',
                onTap: () => onSendMessage(
                  'Explain quantum computing in simple terms',
                ),
              ),
              _SuggestionChip(
                text: 'Write a Python function',
                onTap: () => onSendMessage(
                  'Write a Python function to calculate factorial',
                ),
              ),
              _SuggestionChip(
                text: 'Help me debug code',
                onTap: () => onSendMessage('I need help debugging some code'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      onPressed: onTap,
      label: Text(text),
      backgroundColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
      side: BorderSide.none,
    );
  }
}
