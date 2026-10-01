import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/markdown_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Finished runs remain accessible outside the paginated transcript.
class WorkflowCompletionNotice extends StatefulWidget {
  const WorkflowCompletionNotice({super.key, required this.conversation});
  final Conversation? conversation;

  @override
  State<WorkflowCompletionNotice> createState() =>
      _WorkflowCompletionNoticeState();
}

class _WorkflowCompletionNoticeState extends State<WorkflowCompletionNotice> {
  WorkflowProvider? _workflows;
  bool _retrying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workflows = context.read<WorkflowProvider>();
    if (identical(workflows, _workflows)) return;
    _workflows = workflows;
    _hydrate();
  }

  @override
  void didUpdateWidget(WorkflowCompletionNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation?.id != widget.conversation?.id) _hydrate();
  }

  void _hydrate() {
    final id = widget.conversation?.id;
    if (id != null) unawaited(_workflows!.loadForConversation(id));
  }

  Future<void> _retry() async {
    final id = widget.conversation?.id;
    if (id == null || _retrying) return;
    setState(() => _retrying = true);
    await _workflows!.loadForConversation(id);
    if (mounted) setState(() => _retrying = false);
  }

  Future<void> _dismiss(WorkflowRun run) async {
    try {
      await _workflows!.dismissCompletion(run.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.messageWorkflowDismissFailed,
          ),
        ),
      );
    }
  }

  void _showResult(WorkflowRun run) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final body = [
      run.summary,
      run.error,
    ].whereType<String>().where((text) => text.isNotEmpty).join('\n\n');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          run.succeeded ? l10n.messageWorkflowDone : l10n.messageWorkflowFailed,
        ),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: MarkdownWidget(
              content: body.isEmpty ? l10n.messageWorkflowNoReport : body,
              colorScheme: theme.colorScheme,
              textTheme: theme.textTheme,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    if (conversation == null) return const SizedBox.shrink();
    final workflows = context.watch<WorkflowProvider>();
    final l10n = AppLocalizations.of(context)!;
    if (workflows.hasCompletionLoadError(conversation.id)) {
      return MaterialBanner(
        key: const ValueKey('workflow_completion_load_error'),
        content: Text(l10n.messageWorkflowLoadFailed),
        actions: [
          TextButton(
            key: const ValueKey('workflow_completion_retry'),
            onPressed: _retrying ? null : () => unawaited(_retry()),
            child: Text(l10n.retry),
          ),
        ],
      );
    }
    final run = workflows.pendingCompletionFor(
      conversation.id,
      sessionEpoch: conversation.isPrimary ? conversation.sessionEpoch : null,
    );
    if (run == null) return const SizedBox.shrink();
    return Material(
      key: const ValueKey('workflow_completion_notice'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(run.succeeded ? Icons.task_alt : Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              run.succeeded
                  ? l10n.messageWorkflowDone
                  : l10n.messageWorkflowFailed,
              maxLines: 2,
            ),
          ),
          TextButton(
            key: const ValueKey('workflow_completion_view'),
            onPressed: () => _showResult(run),
            child: Text(l10n.messageWorkflowViewResult),
          ),
          IconButton(
            key: const ValueKey('workflow_completion_dismiss'),
            tooltip: l10n.dismiss,
            onPressed: () => unawaited(_dismiss(run)),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
