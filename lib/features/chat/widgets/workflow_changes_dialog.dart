import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Review-and-apply dialog for a finished workflow's diff (idea 18).
///
/// Nothing the agent did has touched the user's disk yet — this is the gate.
/// Files are selectable so a partial apply is possible, and anything the user
/// edited locally during the run is reported as a conflict afterwards rather
/// than being overwritten.
class WorkflowChangesDialog extends StatefulWidget {
  const WorkflowChangesDialog({
    super.key,
    required this.run,
    required this.folderRoot,
  });

  final WorkflowRun run;
  final String folderRoot;

  @override
  State<WorkflowChangesDialog> createState() => _WorkflowChangesDialogState();
}

class _WorkflowChangesDialogState extends State<WorkflowChangesDialog> {
  List<WorkflowChange>? _changes;
  Set<String> _selected = {};
  String? _error;
  bool _applying = false;
  ApplyResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final changes = await context.read<WorkflowProvider>().fetchChanges(
        widget.run.id,
      );
      if (!mounted) return;
      setState(() {
        _changes = changes;
        _selected = changes
            .where((c) => c.isApplicable)
            .map((c) => c.path)
            .toSet();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final changes = _changes;

    return AlertDialog(
      key: const ValueKey('workflow_changes_dialog'),
      title: Text(l10n.titleWorkflowChanges),
      content: SizedBox(width: 520, child: _content(changes, l10n, theme)),
      actions: _actions(l10n, changes),
    );
  }

  Widget _content(
    List<WorkflowChange>? changes,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: theme.colorScheme.error));
    }
    if (_result != null) return _resultView(l10n, theme);
    if (changes == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (changes.isEmpty) return Text(l10n.messageWorkflowNoChanges);
    return _changeList(changes, l10n, theme);
  }

  Widget _changeList(
    List<WorkflowChange> changes,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.messageWorkflowApplyWarning(widget.folderRoot),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: changes.length,
            itemBuilder: (context, index) {
              final change = changes[index];
              final applicable = change.isApplicable;
              return CheckboxListTile(
                dense: true,
                value: applicable && _selected.contains(change.path),
                onChanged: applicable
                    ? (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(change.path);
                        } else {
                          _selected.remove(change.path);
                        }
                      })
                    : null,
                secondary: Icon(
                  _iconFor(change.status),
                  size: 18,
                  color: _colorFor(change.status, theme),
                ),
                title: Text(
                  change.path,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  applicable
                      ? _labelFor(change, l10n)
                      : l10n.messageWorkflowTooLarge,
                  style: theme.textTheme.labelSmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _resultView(AppLocalizations l10n, ThemeData theme) {
    final result = _result!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.messageWorkflowApplied(result.applied.length)),
        if (result.conflicts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l10n.messageWorkflowConflicts,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          for (final path in result.conflicts)
            Text('• $path', style: theme.textTheme.labelSmall),
        ],
        if (result.failed.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l10n.messageWorkflowFailedFiles,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          for (final path in result.failed)
            Text('• $path', style: theme.textTheme.labelSmall),
        ],
      ],
    );
  }

  List<Widget> _actions(AppLocalizations l10n, List<WorkflowChange>? changes) {
    if (_result != null || _error != null) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _applying ? null : () => Navigator.of(context).pop(),
        child: Text(l10n.cancel),
      ),
      FilledButton(
        key: const ValueKey('workflow_apply_changes'),
        onPressed: (_applying || changes == null || _selected.isEmpty)
            ? null
            : _apply,
        child: _applying
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(l10n.actionApplySelected(_selected.length)),
      ),
    ];
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final result = await context.read<WorkflowProvider>().applyChanges(
      runId: widget.run.id,
      folderRoot: widget.folderRoot,
      changes: _changes!,
      only: _selected,
    );
    if (!mounted) return;
    setState(() {
      _applying = false;
      _result = result;
    });
  }

  IconData _iconFor(String status) => switch (status) {
    'added' => Icons.add_circle_outline,
    'deleted' => Icons.remove_circle_outline,
    _ => Icons.edit_outlined,
  };

  Color _colorFor(String status, ThemeData theme) => switch (status) {
    'added' => Colors.green,
    'deleted' => theme.colorScheme.error,
    _ => theme.colorScheme.primary,
  };

  String _labelFor(WorkflowChange change, AppLocalizations l10n) =>
      switch (change.status) {
        'added' => l10n.labelFileAdded,
        'deleted' => l10n.labelFileDeleted,
        _ => l10n.labelFileModified,
      };
}
