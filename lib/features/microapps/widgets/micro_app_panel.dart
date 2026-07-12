import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/microapps/providers/microapp_panel_controller.dart';
import 'package:garbanzo_ai/features/microapps/services/microapp_service.dart';
import 'package:garbanzo_ai/features/microapps/widgets/micro_app_view.dart';

/// The live micro-app view shown beside the chat. Header (house name + reload /
/// publish / revert / close) over a dumb [MicroAppView]. Used both as a side
/// panel (wide) and a full-screen overlay (narrow).
class MicroAppPanel extends StatelessWidget {
  final MicroappPanelController panel;

  /// Shown on narrow layouts where the panel is an overlay; hidden on wide
  /// layouts where the panel sits permanently beside the chat.
  final bool showCloseAsBack;

  const MicroAppPanel({
    super.key,
    required this.panel,
    this.showCloseAsBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = panel.url;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _Header(panel: panel, showCloseAsBack: showCloseAsBack),
          const Divider(height: 1),
          Expanded(
            child: url == null
                ? const Center(child: Text('No app to display'))
                : MicroAppView(url: url, reloadCounter: panel.reloadCounter),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final MicroappPanelController panel;
  final bool showCloseAsBack;
  const _Header({required this.panel, required this.showCloseAsBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          const Icon(Icons.widgets_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              panel.fileName ?? panel.appTitle ?? 'Micro-App',
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: panel.reload,
          ),
          IconButton(
            tooltip: 'Revert changes',
            icon: const Icon(Icons.undo, size: 20),
            onPressed: () => _revert(context),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.publish, size: 18),
            label: const Text('Publish'),
            onPressed: () => _publish(context),
          ),
          IconButton(
            tooltip: showCloseAsBack ? 'Back to chat' : 'Close panel',
            icon: Icon(
              showCloseAsBack ? Icons.arrow_forward : Icons.close,
              size: 20,
            ),
            onPressed: panel.close,
          ),
        ],
      ),
    );
  }

  Future<void> _publish(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publish changes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Commit and deploy to GitHub Pages.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Commit message (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await MicroappService.instance.publish(
        message: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
      messenger.showSnackBar(SnackBar(content: Text(res.message)));
    } on MicroappApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Publish failed: ${e.detail}')),
      );
    }
  }

  Future<void> _revert(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revert all changes?'),
        content: const Text(
          'Discard every uncommitted change in your workspace. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MicroappService.instance.revert(all: true);
      panel.reload();
      messenger.showSnackBar(const SnackBar(content: Text('Changes reverted')));
    } on MicroappApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Revert failed: ${e.detail}')),
      );
    }
  }
}
