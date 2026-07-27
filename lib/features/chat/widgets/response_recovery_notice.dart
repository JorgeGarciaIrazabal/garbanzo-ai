import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Calm, non-blocking status shown while a dropped SSE response is recovered.
class ResponseRecoveryNotice extends StatelessWidget {
  const ResponseRecoveryNotice({super.key, required this.state});

  final ChatResponseRecoveryState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final waiting = state == ChatResponseRecoveryState.waitingForConnection;

    return Container(
      key: const ValueKey('chat_response_recovery_notice'),
      width: double.infinity,
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            waiting ? Icons.cloud_off_outlined : Icons.cloud_sync_outlined,
            color: colorScheme.onSurfaceVariant,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              waiting
                  ? l10n.messageResponseWaitingForConnection
                  : l10n.messageResponseSyncing,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
