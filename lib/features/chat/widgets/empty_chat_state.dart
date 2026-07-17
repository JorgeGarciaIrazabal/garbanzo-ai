import 'package:flutter/material.dart';
import 'package:garbanzo_ai/core/widgets/brand_mark.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

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
            const BrandMark(size: 88),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.messageStartAConversation,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.messageTypeMessageToBegin,
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
                  text: AppLocalizations.of(
                    context,
                  )!.messageExplainQuantumComputing,
                  onTap: () => onSendMessage(
                    AppLocalizations.of(
                      context,
                    )!.messageExplainQuantumComputing,
                  ),
                ),
                _SuggestionChip(
                  text: AppLocalizations.of(
                    context,
                  )!.messageWriteAPythonFunction,
                  onTap: () => onSendMessage(
                    AppLocalizations.of(
                      context,
                    )!.messageWriteAPythonFunctionPrompt,
                  ),
                ),
                _SuggestionChip(
                  text: AppLocalizations.of(context)!.messageHelpMeDebugCode,
                  onTap: () => onSendMessage(
                    AppLocalizations.of(context)!.messageHelpMeDebugCodePrompt,
                  ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final tips = [
      (Icons.mic_none, l10n.tipVoiceInputTitle, l10n.tipVoiceInputBody),
      (
        Icons.attach_file,
        l10n.tipFilesAndImagesTitle,
        l10n.tipFilesAndImagesBody,
      ),
      (Icons.psychology_outlined, l10n.tipMemoryTitle, l10n.tipMemoryBody),
      (
        Icons.menu_book_outlined,
        l10n.tipKnowledgeBaseTitle,
        l10n.tipKnowledgeBaseBody,
      ),
      (Icons.groups_outlined, l10n.tipRoomsTitle, l10n.tipRoomsBody),
    ];

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
                      AppLocalizations.of(context)!.titleGettingStarted,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: AppLocalizations.of(context)!.labelDismiss,
                    onPressed: onDismiss,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final (icon, title, body) in tips)
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
