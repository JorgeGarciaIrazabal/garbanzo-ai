import 'package:flutter/material.dart';
import 'package:garbanzo_ai/core/widgets/brand_mark.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/mute_sheet.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Visual list of rooms styled to match the conversation list.
///
/// Used in two places: the standalone Rooms page and the in-chat sidebar
/// "Rooms" tab.
class RoomsListView extends StatelessWidget {
  const RoomsListView({
    super.key,
    required this.rooms,
    required this.onSelect,
    required this.onDelete,
    this.onCreate,
    this.onMute,
    this.selectedId,
    this.loading = false,
    this.error,
    this.compact = false,
  });

  final List<Room> rooms;
  final String? selectedId;
  final ValueChanged<Room> onSelect;
  final ValueChanged<Room> onDelete;
  final VoidCallback? onCreate;

  /// Applies a mute choice (`8h` / `1w` / `forever` / `unmute`) to a room.
  /// Long-press / right-click only opens the mute sheet when this is set.
  final void Function(Room room, String duration)? onMute;

  final bool loading;
  final String? error;

  /// Use compact (sidebar) styling when true, full-page tile when false.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (loading && rooms.isEmpty) {
      return const SkeletonList(showAvatar: true);
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $error'),
        ),
      );
    }
    if (rooms.isEmpty) {
      return _EmptyState(onCreate: onCreate);
    }

    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        return _RoomTile(
          room: room,
          isSelected: room.id == selectedId,
          compact: compact,
          colorScheme: theme.colorScheme,
          textTheme: theme.textTheme,
          onTap: () => onSelect(room),
          onDelete: () => _confirmDelete(context, room),
          onMuteMenu: onMute == null
              ? null
              : () => _showMuteSheet(context, room),
        );
      },
    );
  }

  Future<void> _showMuteSheet(BuildContext context, Room room) async {
    final apply = onMute;
    if (apply == null) return;
    final duration = await showMuteSheet(
      context: context,
      name: room.name,
      mutedUntil: room.mutedUntil,
    );
    if (duration != null) apply(room, duration);
  }

  Future<void> _confirmDelete(BuildContext context, Room room) async {
    final ok = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleDeleteRoom),
        content: Text('Delete "${room.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (ok == true) onDelete(room);
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.isSelected,
    required this.compact,
    required this.colorScheme,
    required this.textTheme,
    required this.onTap,
    required this.onDelete,
    this.onMuteMenu,
  });

  final Room room;
  final bool isSelected;
  final bool compact;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Opens the mute sheet — long-press on touch, right-click on desktop.
  final VoidCallback? onMuteMenu;

  @override
  Widget build(BuildContext context) {
    final muted = room.isMuted;
    final unselectedIcon = isSelected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    final subtitle = _subtitle();

    return Material(
      color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // InkWell carries both gestures natively — no wrapper needed.
        onLongPress: onMuteMenu,
        onSecondaryTap: onMuteMenu,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              _Avatar(
                room: room,
                colorScheme: colorScheme,
                isSelected: isSelected,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.name,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (muted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            key: const ValueKey('room_muted_glyph'),
                            Icons.notifications_off,
                            size: 14,
                            semanticLabel: AppLocalizations.of(
                              context,
                            )!.messageRoomMuted,
                            color:
                                (isSelected
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant)
                                    .withValues(alpha: 0.8),
                          ),
                        ],
                        if (room.agentCount > 0) ...[
                          const SizedBox(width: 6),
                          _CountBadge(
                            icon: Icons.smart_toy_outlined,
                            count: room.agentCount,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.7,
                              )
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: AppLocalizations.of(context)!.messageDeleteRoom,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: unselectedIcon,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final desc = room.description?.trim();
    if (desc != null && desc.isNotEmpty) return desc;
    final memberWord = room.memberCount == 1 ? 'member' : 'members';
    final agentWord = room.agentCount == 1 ? 'agent' : 'agents';
    return '${room.memberCount} $memberWord · ${room.agentCount} $agentWord';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.room,
    required this.colorScheme,
    required this.isSelected,
  });

  final Room room;
  final ColorScheme colorScheme;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final initial = room.name.isEmpty
        ? '?'
        : room.name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: isSelected
          ? colorScheme.primary
          : colorScheme.secondaryContainer,
      foregroundColor: isSelected
          ? colorScheme.onPrimary
          : colorScheme.onSecondaryContainer,
      child: Text(
        initial,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 2),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 72),
            const SizedBox(height: 16),
            Text(
              'No rooms yet',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Rooms let you chat with people and AI agents together.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onCreate,
                icon: const Icon(Icons.group_add, size: 18),
                label: Text(AppLocalizations.of(context)!.labelCreateARoom),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
