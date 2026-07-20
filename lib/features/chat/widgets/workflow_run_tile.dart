import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// A delegated opencode run, shown as one quiet expandable line in the
/// transcript — deliberately *not* a card.
///
/// The run needs no decision from the user: it starts on its own, and the
/// diff is **auto-applied** to the user's folder when it finishes. The only
/// feedback the user gets here is the result of that write-back — how many
/// files landed, and any conflicts or write failures. Undo is a separate
/// "revert" native action (see IDEAS.md), not a pre-apply review gate.
class WorkflowRunTile extends StatefulWidget {
  const WorkflowRunTile({super.key, required this.message});

  final ChatMessage message;

  @override
  State<WorkflowRunTile> createState() => _WorkflowRunTileState();
}

class _WorkflowRunTileState extends State<WorkflowRunTile> {
  bool _expanded = false;
  bool _ready = false;
  bool _autoStarted = false;

  /// Providers resolved once, up front, and held as fields.
  ///
  /// This tile lives in a `ListView.builder`, so its element is deactivated
  /// and reparented as the user scrolls. `State.mounted` stays true across
  /// that window, so a `context.read` after an `await` throws "Looking up a
  /// deactivated widget's ancestor is unsafe" no matter how carefully it's
  /// guarded. Reading them synchronously and never touching `context` in the
  /// async paths removes the hazard entirely — both providers are app-scoped
  /// and outlive this widget.
  late final ChatProvider _chat;
  late final WorkflowProvider _workflows;
  bool _wired = false;

  Map<String, dynamic> get _proposal =>
      widget.message.actionProposal ?? const {};
  String get _summary =>
      (_proposal['summary'] as String?) ?? 'Working on your folder';
  String get _instruction {
    final payload = _proposal['payload'];
    if (payload is Map) return (payload['instruction'] as String?) ?? '';
    return '';
  }

  String? get _toolCallId => widget.message.toolCallId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    _chat = context.read<ChatProvider>();
    _workflows = context.read<WorkflowProvider>();
    unawaited(_restoreThenStart());
  }

  /// Re-attach to any existing run first, then start one if there is none.
  ///
  /// The hydrate has to come first: without it, a tile scrolling back into
  /// view (or a reload) would look like a fresh request and launch a second
  /// run of the same task.
  Future<void> _restoreThenStart() async {
    final conversationId = _chat.currentConversation?.id;
    if (conversationId != null) {
      await _workflows.loadForConversation(conversationId);
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _maybeAutoStart();
  }

  void _maybeAutoStart() {
    final toolCallId = _toolCallId;
    if (!_ready || _autoStarted || toolCallId == null) return;
    if (_workflows.runFor(toolCallId) != null) return; // already running/done
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

    final live = phase != WorkflowPhase.done && phase != WorkflowPhase.failed;
    final failed = phase == WorkflowPhase.failed;
    final headerColor = failed
        ? colorScheme.error
        : live
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.75);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('workflow_run_header'),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              hoverColor: colorScheme.onSurface.withValues(alpha: 0.03),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (live)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: colorScheme.primary,
                          value: phase == WorkflowPhase.uploading
                              ? workflows.uploadProgressFor(toolCallId!)
                              : null,
                        ),
                      )
                    else
                      Icon(
                        failed
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 14,
                        color: headerColor,
                      ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _headerLabel(workflows, phase, run),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: headerColor,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 15,
                        color: headerColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) _details(theme, workflows, run, phase),
          // The auto-apply result sits under the header when the run is done,
          // so finished work doesn't look like it vanished. Undo is a separate
          // revert action — no "Review changes" button here anymore.
          if (phase == WorkflowPhase.done && run != null)
            _applyResultLine(theme, workflows, run),
        ],
      ),
    );
  }

  Widget _applyResultLine(
    ThemeData theme,
    WorkflowProvider workflows,
    WorkflowRun run,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final toolCallId = _toolCallId;
    final result = toolCallId == null
        ? null
        : workflows.applyResultFor(toolCallId);
    // No result yet: the apply call is in flight (or about to be).
    if (result == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 6, top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              l10n.messageWorkflowApplying,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final color = (result.conflicts.isEmpty && result.failed.isEmpty)
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    final icon = (result.conflicts.isEmpty && result.failed.isEmpty)
        ? Icons.check_circle_outline
        : Icons.warning_amber_outlined;
    final appliedCount = result.applied.length;
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.messageWorkflowAppliedShort(appliedCount),
              style: theme.textTheme.labelSmall?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Conflict / failure lines for the expanded details view, so a failed
  /// auto-apply doesn't just say "0 applied" without telling the user which
  /// files were involved.
  List<Widget> _applyDetailLines(ThemeData theme, ApplyResult? result) {
    if (result == null) return const [];
    final lines = <Widget>[];
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final err = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.error,
    );
    for (final path in result.conflicts) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${AppLocalizations.of(context)!.messageWorkflowConflictsLabel} $path',
            style: err,
          ),
        ),
      );
    }
    for (final path in result.failed) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${AppLocalizations.of(context)!.messageWorkflowFailedFilesLabel} $path',
            style: err,
          ),
        ),
      );
    }
    for (final path in result.skipped) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${AppLocalizations.of(context)!.messageWorkflowTooLarge}: $path',
            style: muted,
          ),
        ),
      );
    }
    return lines;
  }

  String _headerLabel(
    WorkflowProvider workflows,
    WorkflowPhase phase,
    WorkflowRun? run,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final folder = _folderLabel(run);
    return switch (phase) {
      WorkflowPhase.idle => l10n.messageWorkflowStarting,
      WorkflowPhase.walking => l10n.messageWorkflowScanning,
      WorkflowPhase.uploading =>
        '${l10n.messageWorkflowUploading} '
            '${(workflows.uploadProgressFor(_toolCallId ?? '') * 100).round()}%',
      WorkflowPhase.watching =>
        folder == null
            ? l10n.messageWorkflowRunning
            : l10n.messageWorkflowRunningIn(folder),
      WorkflowPhase.done => l10n.messageWorkflowDone,
      WorkflowPhase.failed => l10n.messageWorkflowFailed,
    };
  }

  String? _folderLabel(WorkflowRun? run) =>
      (run?.scope?['folder_label'] as String?) ??
      _chat.clientFolderNameFor(_chat.currentConversation?.id);

  Widget _details(
    ThemeData theme,
    WorkflowProvider workflows,
    WorkflowRun? run,
    WorkflowPhase phase,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final toolCallId = _toolCallId;
    final error = toolCallId == null ? null : workflows.errorFor(toolCallId);
    final gap = toolCallId == null
        ? null
        : workflows.snapshotGapFor(toolCallId);
    final lastStep = _lastActivity(run);

    return Container(
      margin: const EdgeInsets.only(left: 12, top: 4),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_summary.isNotEmpty) Text(_summary, style: muted),
          if (lastStep != null) ...[
            const SizedBox(height: 4),
            Text(
              lastStep,
              style: muted,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (run?.summary != null && run!.summary!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(run.summary!, style: muted),
          ],
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(error, style: muted?.copyWith(color: theme.colorScheme.error)),
          ],
          if (gap != null && (gap.skipped > 0 || gap.truncated)) ...[
            const SizedBox(height: 4),
            Text(
              gap.truncated
                  ? l10n.messageWorkflowFolderTruncated
                  : l10n.messageWorkflowFilesSkipped(gap.skipped),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (phase == WorkflowPhase.watching) ...[
            const SizedBox(height: 4),
            Text(
              l10n.messageWorkflowKeepsRunning,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (phase == WorkflowPhase.done && toolCallId != null) ...[
            ..._applyDetailLines(theme, workflows.applyResultFor(toolCallId)),
          ],
          if (phase == WorkflowPhase.failed) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: const ValueKey('workflow_retry'),
              onPressed: _start,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(l10n.retry),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
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

  /// Kicks off a run. Deliberately free of `context` — it is called from an
  /// async path where this widget's element may already be deactivated.
  Future<void> _start() async {
    final toolCallId = _toolCallId;
    if (toolCallId == null) return;
    final conversationId = _chat.currentConversation?.id;
    final folder = _chat.clientFolderFor(conversationId);

    if (folder == null) {
      _workflows.reportStartFailure(
        toolCallId,
        'No folder is attached to this chat on this device.',
      );
      return;
    }

    await _workflows.startFromProposal(
      toolCallId: toolCallId,
      instruction: _instruction.isEmpty ? _summary : _instruction,
      folderRoot: folder,
      conversationId: conversationId,
    );
  }
}
