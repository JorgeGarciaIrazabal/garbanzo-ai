import 'package:dio/dio.dart';
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
      child: SafeArea(
        // As an overlay (narrow) the panel covers the whole screen, so the
        // header must clear the status bar; as a side panel (wide) the chat
        // chrome already handles insets.
        top: showCloseAsBack,
        bottom: showCloseAsBack,
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
      ),
    );
  }
}

class _Header extends StatefulWidget {
  final MicroappPanelController panel;
  final bool showCloseAsBack;
  const _Header({required this.panel, required this.showCloseAsBack});

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  // True while a publish or revert request is in flight. Publish/revert can
  // take many seconds (git validate → commit → fetch → rebase → push), so we
  // surface a spinner and disable the mutating actions instead of leaving the
  // header looking frozen.
  bool _busy = false;

  MicroappPanelController get panel => widget.panel;
  bool get showCloseAsBack => widget.showCloseAsBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (showCloseAsBack)
            IconButton(
              tooltip: 'Back to chat',
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: panel.close,
            )
          else ...[
            const SizedBox(width: 4),
            const Icon(Icons.widgets_outlined, size: 18),
            const SizedBox(width: 8),
          ],
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
            onPressed: _busy ? null : _revert,
          ),
          _publishControl(theme),
          // Close only sits in the header on wide layouts; narrow uses the
          // back arrow above.
          if (!showCloseAsBack)
            IconButton(
              tooltip: 'Close panel',
              icon: const Icon(Icons.close, size: 20),
              onPressed: panel.close,
            ),
        ],
      ),
    );
  }

  /// The Publish action, swapping in a spinner while a request is in flight.
  /// Icon-only on phones (a labelled button would crowd out the title).
  Widget _publishControl(ThemeData theme) {
    if (showCloseAsBack) {
      return IconButton(
        tooltip: 'Publish',
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.publish, size: 20),
        onPressed: _busy ? null : _publish,
      );
    }
    return FilledButton.icon(
      icon: _busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : const Icon(Icons.publish, size: 18),
      label: Text(_busy ? 'Publishing…' : 'Publish'),
      onPressed: _busy ? null : _publish,
    );
  }

  Future<void> _publish() async {
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
    final rawMessage = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final res = await MicroappService.instance.publish(
        message: rawMessage.isEmpty ? null : rawMessage,
      );
      messenger.showSnackBar(SnackBar(content: Text(res.message)));
    } on MicroappApiException catch (e) {
      if (mounted) await _showError('Publish failed', e.detail);
    } catch (e) {
      if (mounted) await _showError('Publish failed', _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revert() async {
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

    setState(() => _busy = true);
    try {
      await MicroappService.instance.revert(all: true);
      panel.reload();
      messenger.showSnackBar(const SnackBar(content: Text('Changes reverted')));
    } on MicroappApiException catch (e) {
      if (mounted) await _showError('Revert failed', e.detail);
    } catch (e) {
      if (mounted) await _showError('Revert failed', _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A readable message for a non-API error (network drop, timeout, …).
  String _describe(Object error) {
    if (error is DioException) {
      return error.message ?? 'Could not reach the server. Please try again.';
    }
    return error.toString();
  }

  /// Show a failure in a dialog: git errors (e.g. a rebase conflict) can be
  /// long and multi-line, which a snackbar would truncate.
  Future<void> _showError(String title, String message) {
    return showAnimatedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
