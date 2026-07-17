import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

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
    final result = await showAnimatedDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.titleEditMessage),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 420, maxWidth: 600),
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              minLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(AppLocalizations.of(context)!.saveAndRerun),
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
      label: AppLocalizations.of(context)!.tooltipEdit,
      tooltip: AppLocalizations.of(context)!.messageEditThisMessage,
      onTap: enabled ? () => _openDialog(context) : null,
    );
  }
}
