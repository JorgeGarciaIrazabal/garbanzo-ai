import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Calm, inline status for a room's live connection.
///
/// Routine reconnects never block the room. A stronger (but still inline)
/// treatment appears only after retries are exhausted or the server ends the
/// session.
class RoomConnectionBanner extends StatelessWidget {
  const RoomConnectionBanner({
    super.key,
    required this.state,
    required this.backOnline,
    required this.onRetry,
  });

  final RoomConnectionState state;
  final bool backOnline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    if (state == RoomConnectionState.reconnecting) {
      return _StatusBar(
        key: const ValueKey('room_reconnecting_banner'),
        color: colors.surfaceContainerHighest,
        foregroundColor: colors.onSurfaceVariant,
        leading: SizedBox.square(
          dimension: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.onSurfaceVariant,
          ),
        ),
        message: strings.messageRoomReconnecting,
      );
    }

    if (state == RoomConnectionState.connected && backOnline) {
      return _StatusBar(
        key: const ValueKey('room_back_online_banner'),
        color: colors.tertiaryContainer,
        foregroundColor: colors.onTertiaryContainer,
        leading: Icon(
          Icons.check_circle_outline,
          size: 16,
          color: colors.onTertiaryContainer,
        ),
        message: strings.messageRoomBackOnline,
      );
    }

    if (state == RoomConnectionState.failed ||
        state == RoomConnectionState.closed) {
      return _StatusBar(
        key: const ValueKey('room_connection_failed_banner'),
        color: colors.errorContainer,
        foregroundColor: colors.onErrorContainer,
        leading: Icon(
          Icons.cloud_off_outlined,
          size: 16,
          color: colors.onErrorContainer,
        ),
        message: state == RoomConnectionState.failed
            ? strings.messageRoomReconnectFailed
            : strings.messageRoomConnectionEnded,
        trailing: TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: colors.onErrorContainer,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(strings.tryAgain),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    super.key,
    required this.color,
    required this.foregroundColor,
    required this.leading,
    required this.message,
    this.trailing,
  });

  final Color color;
  final Color foregroundColor;
  final Widget leading;
  final String message;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: foregroundColor, fontSize: 13),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
