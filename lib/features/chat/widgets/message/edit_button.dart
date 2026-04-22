import 'package:flutter/material.dart';

/// Compact "Edit" button for user messages.
///
/// Opens a dialog that lets the user rewrite the message; on save it calls
/// [onSubmit] with the new content.
class EditMessageButton extends StatelessWidget {
  const EditMessageButton({
    super.key,
    required this.content,
    required this.onSubmit,
    this.enabled = true,
  });

  final String content;
  final ValueChanged<String> onSubmit;
  final bool enabled;

  Future<void> _openDialog(BuildContext context) async {
    final controller = TextEditingController(text: content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit message'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 420, maxWidth: 600),
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              minLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save & rerun'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty && result != content) {
      onSubmit(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return InkWell(
      onTap: enabled ? () => _openDialog(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, size: 14, color: color),
            const SizedBox(width: 4),
            Text('Edit', style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
