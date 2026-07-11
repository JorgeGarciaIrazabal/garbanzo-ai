import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';

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
  final bool loading;
  final String? error;

  /// Use compact (sidebar) styling when true, full-page tile when false.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (loading && rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete room?'),
        content: Text('Delete "${room.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
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
  });

  final Room room;
  final bool isSelected;
  final bool compact;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final unselectedIcon = isSelected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    final subtitle = _subtitle();

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                            ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete room',
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
    final initial = room.name.isEmpty ? '?' : room.name.characters.first.toUpperCase();
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
            Icon(
              Icons.group_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No rooms yet',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Rooms let you chat with people and AI agents together.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onCreate,
                icon: const Icon(Icons.group_add, size: 18),
                label: const Text('Create a room'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
