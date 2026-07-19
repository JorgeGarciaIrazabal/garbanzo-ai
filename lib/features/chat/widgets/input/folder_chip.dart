import 'package:flutter/material.dart';

import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Chip shown above the composer when a folder is attached to the conversation.
///
/// Surfaces the bound scope so the user knows which folder the agent can read,
/// with a remove affordance that detaches it.
class FolderChip extends StatelessWidget {
  const FolderChip({
    super.key,
    required this.folderPath,
    required this.onRemove,
  });

  final String folderPath;
  final VoidCallback onRemove;

  String get _basename {
    final parts = folderPath.split(RegExp(r'[/\\]'))
      ..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? folderPath : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l10n.messageFolderScope(_basename),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
