import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/workflow_changes_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Confirm/Cancel card for a `delegate_workflow` proposal (idea 18), plus the
/// live timeline of the run it starts.
///
/// Split out of [ActionProposalCard] because this proposal doesn't finish when
/// the user taps Confirm — that's when a minutes-long run *begins*. State
/// therefore lives in [WorkflowProvider] (which survives this widget being
/// scrolled out of the list) and is hydrated from the server by
/// `tool_call_id`, so a reload or a restart still finds the run.
class WorkflowProposalCard extends StatefulWidget {
  const WorkflowProposalCard({super.key, required this.message});

  final ChatMessage message;

  @override
  State<WorkflowProposalCard> createState() => _WorkflowProposalCardState();
}

class _WorkflowProposalCardState extends State<WorkflowProposalCard> {
  bool _ready = false;
  bool _autoStarted = false;

  Map<String, dynamic> get _proposal =>
      widget.message.actionProposal ?? const {};
  String get _summary =>
      (_proposal['summary'] as String?) ?? 'Delegate this task';
  String get _instruction {
    final payload = _proposal['payload'];
    if (payload is Map) return (payload['instruction'] as String?) ?? '';
    return '';
  }

  String? get _toolCallId => widget.message.toolCallId;

  @override
  void initState() {
    super.initState();
    _restoreThenStart();
  }

  /// Re-attach to any existing run first, then start one if there is none.
  ///
  /// The hydrate has to come first: without it, a card scrolling back into
  /// view (or a reload) would look like a fresh proposal and launch a second
  /// run of the same task.
  Future<void> _restoreThenStart() async {
    final chat = context.read<ChatProvider>();
    final workflows = context.read<WorkflowProvider>();
    final conversationId = chat.currentConversation?.id;
    if (conversationId != null) {
      await workflows.loadForConversation(conversationId);
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _maybeAutoStart();
  }

  /// The model decided this task needs the agent, so it just runs — asking a
  /// second time adds nothing, because the real gate is downstream: the diff
  /// is reviewed file-by-file before anything is written to disk.
  void _maybeAutoStart() {
    final toolCallId = _toolCallId;
    if (!_ready || _autoStarted || toolCallId == null) return;
    final workflows = context.read<WorkflowProvider>();
    if (workflows.runFor(toolCallId) != null) return; // already running/done
    _autoStarted = true;
    unawaited(_start());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final workflows = context.watch<WorkflowProvider>();
    final toolCallId = _toolCallId;
    final run = toolCallId == null ? null : workflows.runFor(toolCallId);
    final phase = toolCallId == null
        ? WorkflowPhase.idle
        : workflows.phaseFor(toolCallId);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          key: const ValueKey('workflow_proposal_card'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_motion_outlined,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.titleDelegateWorkflow,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_summary, style: theme.textTheme.bodyMedium),
                ..._scopeLines(theme, run),
                ..._snapshotGapLine(theme, workflows),
                const SizedBox(height: 12),
                _body(context, workflows, run, phase),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _scopeLines(ThemeData theme, WorkflowRun? run) {
    final chat = context.read<ChatProvider>();
    final folder = chat.clientFolderFor(chat.currentConversation?.id);
    final label =
        (run?.scope?['folder_label'] as String?) ??
        folder?.split(RegExp(r'[/\\]')).last;
    final lines = <String>[
      if (label != null)
        AppLocalizations.of(context)!.messageWorkflowScope(label),
      if (_instruction.isNotEmpty && _instruction != _summary) _instruction,
    ];
    if (lines.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            line,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }

  /// Warn when the snapshot didn't cover the whole folder — the agent can't
  /// act on what it never received, and silence would imply it could.
  List<Widget> _snapshotGapLine(ThemeData theme, WorkflowProvider workflows) {
    final toolCallId = _toolCallId;
    final gap = toolCallId == null
        ? null
        : workflows.snapshotGapFor(toolCallId);
    if (gap == null || (gap.skipped == 0 && !gap.truncated)) return const [];
    final l10n = AppLocalizations.of(context)!;
    return [
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              gap.truncated
                  ? l10n.messageWorkflowFolderTruncated
                  : l10n.messageWorkflowFilesSkipped(gap.skipped),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _body(
    BuildContext context,
    WorkflowProvider workflows,
    WorkflowRun? run,
    WorkflowPhase phase,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final toolCallId = _toolCallId;
    final error = toolCallId == null ? null : workflows.errorFor(toolCallId);

    switch (phase) {
      case WorkflowPhase.walking:
        return _progressRow(l10n.messageWorkflowScanning, null);
      case WorkflowPhase.uploading:
        return _progressRow(
          l10n.messageWorkflowUploading,
          workflows.uploadProgressFor(toolCallId!),
        );
      case WorkflowPhase.watching:
        return _running(run, l10n);
      case WorkflowPhase.done:
        return _finished(context, workflows, run!, l10n);
      case WorkflowPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _status(
              Icons.error_outline,
              error ?? l10n.messageWorkflowFailed,
              colorScheme.error,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('workflow_retry'),
              onPressed: _start,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.retry),
            ),
          ],
        );
      case WorkflowPhase.idle:
        // Auto-start is in flight (or about to be) — never a dead card.
        return _progressRow(l10n.messageWorkflowStarting, null);
    }
  }

  Widget _running(WorkflowRun? run, AppLocalizations l10n) {
    final last = _lastActivity(run);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _progressRow(l10n.messageWorkflowRunning, null),
        if (last != null) ...[
          const SizedBox(height: 6),
          Text(
            last,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          l10n.messageWorkflowKeepsRunning,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// The most recent thing the agent did, for a one-line "what's happening".
  String? _lastActivity(WorkflowRun? run) {
    if (run == null || run.progress.isEmpty) return null;
    for (final entry in run.progress.reversed) {
      final type = entry['type'];
      if (type == 'tool_call') {
        final calls = entry['tool_calls'];
        if (calls is List && calls.isNotEmpty) {
          final name = (calls.first as Map)['name'];
          if (name != null) return '$name…';
        }
      } else if (type == 'chunk') {
        final content = (entry['content'] as String?)?.trim();
        if (content != null && content.isNotEmpty) return content;
      }
    }
    return null;
  }

  Widget _finished(
    BuildContext context,
    WorkflowProvider workflows,
    WorkflowRun run,
    AppLocalizations l10n,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _status(
          Icons.check_circle_outline,
          l10n.messageWorkflowDone,
          colorScheme.primary,
        ),
        if (run.summary != null && run.summary!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(run.summary!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          key: const ValueKey('workflow_review_changes'),
          onPressed: () => _review(context, run),
          icon: const Icon(Icons.difference_outlined, size: 18),
          label: Text(l10n.actionReviewChanges),
        ),
      ],
    );
  }

  Widget _progressRow(String label, double? value) {
    return Row(
      children: [
        SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2, value: value),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value == null ? label : '$label ${(value * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _status(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }

  Future<void> _start() async {
    final toolCallId = _toolCallId;
    if (toolCallId == null) return;
    final chat = context.read<ChatProvider>();
    final workflows = context.read<WorkflowProvider>();
    final conversationId = chat.currentConversation?.id;
    final folder = chat.clientFolderFor(conversationId);

    if (folder == null) {
      workflows.reportStartFailure(
        toolCallId,
        'No folder is attached to this chat on this device.',
      );
      return;
    }

    await workflows.startFromProposal(
      toolCallId: toolCallId,
      instruction: _instruction.isEmpty ? _summary : _instruction,
      folderRoot: folder,
      conversationId: conversationId,
    );
  }

  Future<void> _review(BuildContext context, WorkflowRun run) async {
    final chat = context.read<ChatProvider>();
    final folder = chat.clientFolderFor(chat.currentConversation?.id);
    if (folder == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => WorkflowChangesDialog(run: run, folderRoot: folder),
    );
  }
}
