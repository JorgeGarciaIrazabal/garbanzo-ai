import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../settings/providers/settings_provider.dart';

/// Shown when no conversation is active — prompts the user to start chatting.
class EmptyChatState extends StatelessWidget {
  const EmptyChatState({super.key, required this.onSendMessage});

  final ValueChanged<String> onSendMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsProvider>();
    final showOnboarding = settings.loaded && !settings.onboardingDismissed;

    return Center(
      child: SingleChildScrollView(
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
          if (showOnboarding) ...[
            const SizedBox(height: 24),
            _GettingStartedCard(
              onDismiss: () =>
                  context.read<SettingsProvider>().dismissOnboarding(),
            ),
          ],
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
      ),
    );
  }
}

/// One-time tour of the features new users won't discover on their own.
/// Dismissal is persisted via [SettingsProvider.dismissOnboarding].
class _GettingStartedCard extends StatelessWidget {
  const _GettingStartedCard({required this.onDismiss});

  final VoidCallback onDismiss;

  static const _tips = [
    (
      Icons.mic_none,
      'Voice input',
      'Tap the mic to dictate — your speech is transcribed locally.',
    ),
    (
      Icons.attach_file,
      'Files & images',
      'Attach or drag in PDFs, spreadsheets, code, and pictures.',
    ),
    (
      Icons.psychology_outlined,
      'Memory',
      'The assistant learns facts about you over time — review them '
          'anytime under Settings → Memories.',
    ),
    (
      Icons.menu_book_outlined,
      'Knowledge base',
      'Upload documents once, then ask questions about them in any chat.',
    ),
    (
      Icons.groups_outlined,
      'Rooms',
      'Create rooms where several AI agents (and people) chat together.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Getting started',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Dismiss',
                    onPressed: onDismiss,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final (icon, title, body) in _tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, right: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$title — ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              TextSpan(
                                text: body,
                                style: theme.textTheme.bodySmall?.copyWith(
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
            ],
          ),
        ),
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
