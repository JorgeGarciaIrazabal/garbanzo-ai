import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';

/// Mute durations understood by `PATCH /rooms/{id}/members/me/mute`.
const muteDuration8h = '8h';
const muteDuration1w = '1w';
const muteDurationForever = 'forever';
const muteDurationUnmute = 'unmute';

/// Bottom sheet offering the room mute options.
///
/// Resolves to the chosen duration string (`8h` / `1w` / `forever` /
/// `unmute`), or null when dismissed. "Unmute" is only offered while the room
/// is actually muted.
///
/// Follows the room panel's sheet style in `room_chat_view.dart`
/// (`showModalBottomSheet` + `showDragHandle`).
Future<String?> showMuteRoomSheet({
  required BuildContext context,
  required String roomName,
  required DateTime? mutedUntil,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) =>
        _MuteRoomSheet(roomName: roomName, mutedUntil: mutedUntil),
  );
}

class _MuteRoomSheet extends StatelessWidget {
  const _MuteRoomSheet({required this.roomName, required this.mutedUntil});

  final String roomName;
  final DateTime? mutedUntil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final muted = isMuteActive(mutedUntil);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  muted ? 'Notifications muted' : 'Mute notifications',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  muted ? muteStatusLabel(mutedUntil) : roomName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _MuteOption(
            key: const ValueKey('mute_option_8h'),
            icon: Icons.schedule,
            label: '8 hours',
            onTap: () => Navigator.of(context).pop(muteDuration8h),
          ),
          _MuteOption(
            key: const ValueKey('mute_option_1w'),
            icon: Icons.date_range,
            label: '1 week',
            onTap: () => Navigator.of(context).pop(muteDuration1w),
          ),
          _MuteOption(
            key: const ValueKey('mute_option_forever'),
            icon: Icons.notifications_off_outlined,
            label: 'Always',
            onTap: () => Navigator.of(context).pop(muteDurationForever),
          ),
          if (muted)
            _MuteOption(
              key: const ValueKey('mute_option_unmute'),
              icon: Icons.notifications_active_outlined,
              label: 'Unmute',
              color: colorScheme.primary,
              onTap: () => Navigator.of(context).pop(muteDurationUnmute),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MuteOption extends StatelessWidget {
  const _MuteOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

/// Human-readable mute status, e.g. "Muted until 14:30" / "Muted always".
///
/// Never prints the forever-sentinel's literal year-9999 date. [now] is
/// injectable so tests can pin the "is it today?" decision.
String muteStatusLabel(DateTime? mutedUntil, {DateTime? now}) {
  if (!isMuteActive(mutedUntil, now: now)) return 'Not muted';
  if (isMuteForever(mutedUntil)) return 'Muted always';
  return 'Muted until ${_formatUntil(mutedUntil!, now ?? DateTime.now())}';
}

/// Local-time formatting consistent with `room_message_bubble._formatTime`;
/// a date prefix is added once the expiry is off today (an "8h" mute can land
/// tomorrow, a "1w" one always does).
String _formatUntil(DateTime until, DateTime now) {
  final local = until.toLocal();
  final time = '${_two(local.hour)}:${_two(local.minute)}';
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) return time;
  return '${_months[local.month - 1]} ${local.day}, $time';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');
