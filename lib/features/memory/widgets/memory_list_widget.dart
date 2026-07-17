import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/memory/models/memory.dart';
import 'package:garbanzo_ai/features/memory/widgets/memory_item_tile.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Scrollable list of memories with empty state handling.
class MemoryListWidget extends StatelessWidget {
  const MemoryListWidget({
    super.key,
    required this.memories,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final List<Memory> memories;
  final Function(Memory memory) onEdit;
  final Function(Memory memory) onDelete;
  final Function(Memory memory) onToggleActive;

  @override
  Widget build(BuildContext context) {
    if (memories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.messageNoMemoriesYet,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.messageMemoriesStoreFactsHint,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final memory = memories[index];
        return MemoryItemTile(
          memory: memory,
          onEdit: () => onEdit(memory),
          onDelete: () => onDelete(memory),
          onToggleActive: () => onToggleActive(memory),
        );
      },
    );
  }
}
