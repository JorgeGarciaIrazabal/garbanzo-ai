import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class VisionModelWarningDialog extends StatelessWidget {
  const VisionModelWarningDialog({
    required this.currentModelName,
    required this.choices,
    super.key,
  });

  final String currentModelName;
  final List<VisionModelChoice> choices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: colorScheme.onTertiaryContainer,
        size: 32,
      ),
      iconColor: colorScheme.onTertiaryContainer,
      backgroundColor: colorScheme.surface,
      title: Text(l10n.titleVisionModelWarning),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.messageVisionModelRequired(currentModelName),
                style: TextStyle(color: colorScheme.onTertiaryContainer),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.messageVisionSettingsPreserved,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (choices.isEmpty) ...[
              const SizedBox(height: 16),
              Text(l10n.errorNoVisionModelAvailable(currentModelName)),
            ] else ...[
              const SizedBox(height: 16),
              for (final choice in choices) ...[
                _VisionModelOption(choice: choice),
                if (choice != choices.last) const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _VisionModelOption extends StatelessWidget {
  const _VisionModelOption({required this.choice});

  final VisionModelChoice choice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final (title, subtitle, icon) = switch (choice.kind) {
      VisionModelChoiceKind.faster => (
        l10n.titleVisionModelFast,
        l10n.descriptionVisionModelFast,
        Icons.bolt_rounded,
      ),
      VisionModelChoiceKind.smarter => (
        l10n.titleVisionModelSmart,
        l10n.descriptionVisionModelSmart,
        Icons.psychology_alt_rounded,
      ),
      VisionModelChoiceKind.compatible => (
        choice.model.name,
        l10n.descriptionVisionModelCompatible,
        Icons.visibility_outlined,
      ),
    };

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('vision_model_choice_${choice.model.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).pop(choice),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
