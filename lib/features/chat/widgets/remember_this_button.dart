import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/memory/providers/memory_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// A button that allows users to save selected text or entire message content as a memory.
///
/// Opens a dialog with pre-filled content that can be edited before saving.
class RememberThisButton extends StatelessWidget {
  const RememberThisButton({
    super.key,
    required this.content,
    this.sourceConversationId,
    this.iconSize = 14,
    this.textSize = 12,
  });

  final String content;
  final String? sourceConversationId;
  final double iconSize;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _showRememberDialog(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: iconSize,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context)!.labelRemember,
              style: TextStyle(
                fontSize: textSize,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRememberDialog(BuildContext context) {
    final controller = TextEditingController(text: content);
    final colorScheme = Theme.of(context).colorScheme;
    final memoryProvider = context.read<MemoryProvider>();

    final l10n = AppLocalizations.of(context)!;

    showAnimatedDialog(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider.value(
        value: memoryProvider,
        child: AlertDialog(
          title: Text(l10n.titleRememberThis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.messageRememberDescription,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: l10n.hintMemoryContent,
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                minLines: 3,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            Consumer<MemoryProvider>(
              builder: (context, provider, child) {
                final isLoading = provider.isCreating;
                return FilledButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final memoryContent = controller.text.trim();
                          if (memoryContent.isEmpty) return;

                          Navigator.of(dialogContext).pop();

                          try {
                            await provider.createMemory(
                              content: memoryContent,
                              sourceConversationId: sourceConversationId,
                            );

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.messageMemorySaved),
                                  backgroundColor: colorScheme.primary,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.messageFailedToSaveMemory(
                                      e.toString(),
                                    ),
                                  ),
                                  backgroundColor: colorScheme.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.save),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
