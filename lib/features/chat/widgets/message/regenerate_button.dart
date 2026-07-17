import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

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
      label: AppLocalizations.of(context)!.messageRegenerateTitle,
      tooltip: AppLocalizations.of(context)!.messageDeleteResponseRegenerate,
      onTap: enabled ? onPressed : null,
    );
  }
}
