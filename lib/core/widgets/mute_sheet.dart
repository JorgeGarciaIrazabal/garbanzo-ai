import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/mute_util.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Bottom sheet offering mute duration options.
///
/// Resolves to the chosen duration string (`8h` / `1w` / `forever` /
/// `unmute`), or null when dismissed. "Unmute" is only offered while the
/// target is actually muted.
///
/// Shared by rooms (`PATCH /rooms/{id}/members/me/mute`) and conversations
/// (`PATCH /chat/conversations/{id}/mute`) — both mute mechanisms present the
/// exact same choice, so there is only one sheet implementation.
///
/// [name] is the room name or conversation title shown as the sheet
/// subtitle when not muted. Follows the room panel's sheet style
/// (`showModalBottomSheet` + `showDragHandle`).
Future<String?> showMuteSheet({
  required BuildContext context,
  required String name,
  required DateTime? mutedUntil,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _MuteSheet(name: name, mutedUntil: mutedUntil),
  );
}

class _MuteSheet extends StatelessWidget {
  const _MuteSheet({required this.name, required this.mutedUntil});

  final String name;
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
                  muted ? muteStatusLabel(mutedUntil) : name,
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
            label: AppLocalizations.of(context)!.labelEightHours,
            onTap: () => Navigator.of(context).pop(muteDuration8h),
          ),
          _MuteOption(
            key: const ValueKey('mute_option_1w'),
            icon: Icons.date_range,
            label: AppLocalizations.of(context)!.labelOneWeek,
            onTap: () => Navigator.of(context).pop(muteDuration1w),
          ),
          _MuteOption(
            key: const ValueKey('mute_option_forever'),
            icon: Icons.notifications_off_outlined,
            label: AppLocalizations.of(context)!.labelAlways,
            onTap: () => Navigator.of(context).pop(muteDurationForever),
          ),
          if (muted)
            _MuteOption(
              key: const ValueKey('mute_option_unmute'),
              icon: Icons.notifications_active_outlined,
              label: AppLocalizations.of(context)!.messageUnmute,
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
