import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/memory/models/memory.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Individual memory tile displaying content, source, and status.
class MemoryItemTile extends StatelessWidget {
  const MemoryItemTile({
    super.key,
    required this.memory,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final Memory memory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  String _formatDateTime(BuildContext context, DateTime dateTime) {
    final l10n = AppLocalizations.of(context)!;
    final months = l10n.labelMonthNames.split(',');
    final month = months[dateTime.month - 1];
    final day = dateTime.day;
    final year = dateTime.year;
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return l10n.messageMonthDayYearTime(
      month,
      day.toString(),
      year.toString(),
      displayHour.toString(),
      minute,
      amPm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with status indicator
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: memory.isActive
                        ? Colors.green
                        : Colors.grey.shade400,
                  ),
                  child: Tooltip(
                    message: memory.isActive
                        ? AppLocalizations.of(context)!.active
                        : AppLocalizations.of(context)!.inactive,
                    child: const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memory.content,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: memory.isActive
                              ? TextDecoration.none
                              : TextDecoration.lineThrough,
                          color: memory.isActive ? null : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Source and timestamp
                      Text(
                        AppLocalizations.of(context)!.messageCreatedAt(
                          _formatDateTime(context, memory.createdAt),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (memory.sourceConversationId != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.messageSourceConversation,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Action buttons
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: onEdit,
                      tooltip: AppLocalizations.of(context)!.tooltipEditMemory,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 20,
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: Icon(
                        memory.isActive ? Icons.toggle_on : Icons.toggle_off,
                      ),
                      onPressed: onToggleActive,
                      tooltip: memory.isActive
                          ? AppLocalizations.of(
                              context,
                            )!.tooltipDeactivateMemory
                          : AppLocalizations.of(context)!.tooltipActivateMemory,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 24,
                      color: memory.isActive ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onDelete,
                      tooltip: AppLocalizations.of(
                        context,
                      )!.tooltipDeleteMemory,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 20,
                      color: Colors.red.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
