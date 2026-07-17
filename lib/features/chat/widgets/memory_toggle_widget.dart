import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// A toggle switch to enable/disable memory injection for the current conversation.
///
/// Toggling this updates the conversation's `useMemory` flag via the API.
class MemoryToggleWidget extends StatefulWidget {
  const MemoryToggleWidget({super.key});

  @override
  State<MemoryToggleWidget> createState() => _MemoryToggleWidgetState();
}

class _MemoryToggleWidgetState extends State<MemoryToggleWidget> {
  bool _isUpdating = false;

  Future<void> _toggleMemory() async {
    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.currentConversation;

    if (conversation == null) return;

    setState(() => _isUpdating = true);

    try {
      await chatProvider.updateConversation(useMemory: !conversation.useMemory);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update memory setting: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.currentConversation;

    if (conversation == null) {
      return const SizedBox.shrink();
    }

    final useMemory = conversation.useMemory;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_border, size: 18, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context)!.titleMemory,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 4),
          Switch(
            value: useMemory,
            onChanged: _isUpdating ? null : (_) => _toggleMemory(),
            activeThumbColor: Theme.of(context).colorScheme.primary,
            activeTrackColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.5),
          ),
          if (_isUpdating) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}
