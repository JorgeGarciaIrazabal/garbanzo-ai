import 'package:flutter/material.dart';

import 'message_action_button.dart';

/// Compact "Regenerate" button for the last assistant message.
class RegenerateButton extends StatelessWidget {
  const RegenerateButton({
    super.key,
    required this.onPressed,
    this.enabled = true,
  });

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MessageActionButton(
      icon: Icons.refresh,
      label: 'Regenerate',
      tooltip: 'Delete this response and generate a new one',
      onTap: enabled ? onPressed : null,
    );
  }
}
