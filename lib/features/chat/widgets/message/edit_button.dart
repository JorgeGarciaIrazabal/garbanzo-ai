import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';

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
    return MessageActionButton(
      icon: Icons.edit_outlined,
      label: 'Edit',
      tooltip: 'Edit this message and rerun the conversation from here',
      onTap: enabled ? () => _openDialog(context) : null,
    );
  }
}
