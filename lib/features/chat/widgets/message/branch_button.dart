import 'package:flutter/material.dart';

import 'message_action_button.dart';

class BranchButton extends StatelessWidget {
  const BranchButton({super.key, required this.onPressed, this.enabled = true});

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MessageActionButton(
      icon: Icons.call_split,
      label: 'Branch',
      tooltip: 'Fork a new conversation from this point',
      onTap: enabled ? onPressed : null,
    );
  }
}
