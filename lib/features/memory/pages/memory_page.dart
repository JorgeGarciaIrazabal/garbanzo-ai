import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/memory/models/memory.dart';
import 'package:garbanzo_ai/features/memory/providers/memory_provider.dart';
import 'package:garbanzo_ai/features/memory/widgets/memory_list_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Main page for viewing, editing, and managing memories.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  // App-level provider (see main.dart) — shared with the chat page's
  // memory toggle, so edits here are visible there immediately.
  MemoryProvider get _provider => context.read<MemoryProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.refreshMemories();
    });
  }

  void _showCreateMemoryDialog() {
    final controller = TextEditingController();

    showAnimatedDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleCreateMemoryAction),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.hintEnterMemoryContent,
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isEmpty) return;
              Navigator.of(context).pop();
              await _provider.createMemory(content: content);
            },
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
  }

  void _showEditMemoryDialog(Memory memory) {
    final controller = TextEditingController(text: memory.content);

    showAnimatedDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleEditMemoryAction),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.hintEnterMemoryContent,
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isEmpty) return;
              Navigator.of(context).pop();
              await _provider.updateMemory(
                memoryId: memory.id,
                content: content,
              );
            },
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(Memory memory) {
    showAnimatedDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleDeleteMemoryAction),
        content: Text(
          'Are you sure you want to delete this memory?\n\n"${memory.content}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(context).pop();
              await _provider.deactivateMemory(memory.id);
            },
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MemoryProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.titleMemories),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: provider.isLoading ? null : _showCreateMemoryDialog,
            tooltip: AppLocalizations.of(context)!.messageCreateNewMemory,
          ),
        ],
      ),
      body: provider.isLoading && provider.memories.isEmpty
          ? const SkeletonList()
          : Stack(
              children: [
                // Memory list
                MemoryListWidget(
                  memories: provider.memories,
                  onEdit: _showEditMemoryDialog,
                  onDelete: _showDeleteConfirmationDialog,
                  onToggleActive: (memory) =>
                      provider.toggleMemoryActive(memory.id, memory.isActive),
                ),

                // Loading overlay
                if (provider.isLoading)
                  Container(
                    color: Colors.black12,
                    child: const Center(child: CircularProgressIndicator()),
                  ),

                // Error snackbar
                if (provider.error != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: SnackBar(
                      content: Text(provider.error!),
                      backgroundColor: Colors.red,
                      action: SnackBarAction(
                        label: AppLocalizations.of(context)!.labelDismiss,
                        textColor: Colors.white,
                        onPressed: () => provider.clearError(),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: provider.isLoading ? null : _showCreateMemoryDialog,
        tooltip: AppLocalizations.of(context)!.messageCreateMemory,
        child: const Icon(Icons.add),
      ),
    );
  }
}
