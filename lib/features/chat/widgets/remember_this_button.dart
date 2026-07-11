import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/memory/providers/memory_provider.dart';

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
              'Remember',
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

    showDialog(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider.value(
        value: memoryProvider,
        child: AlertDialog(
        title: const Text('Remember This'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save this content as a memory for future reference:',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Memory content',
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
            child: const Text('Cancel'),
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
                                content: const Text('Memory saved successfully'),
                                backgroundColor: colorScheme.primary,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to save memory: $e'),
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
                    : const Text('Save'),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}
