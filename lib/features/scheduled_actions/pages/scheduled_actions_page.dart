import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/scheduled_actions/models/scheduled_action.dart';
import 'package:garbanzo_ai/features/scheduled_actions/providers/scheduled_actions_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class ScheduledActionsPage extends StatelessWidget {
  const ScheduledActionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScheduledActionsProvider()..load(),
      child: const _ScheduledActionsView(),
    );
  }
}

class _ScheduledActionsView extends StatelessWidget {
  const _ScheduledActionsView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScheduledActionsProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.titleScheduledActions),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.tooltipRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: provider.loading ? null : provider.load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context)!.tooltipNew),
      ),
      body: Stack(
        children: [
          if (provider.loading && provider.actions.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (provider.actions.isEmpty)
            _emptyState(theme)
          else
            RefreshIndicator(
              onRefresh: provider.load,
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: provider.actions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) =>
                    _ActionTile(action: provider.actions[i]),
              ),
            ),
          if (provider.error != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider.error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss error',
                        icon: const Icon(Icons.close),
                        onPressed: provider.clearError,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return ListView(
      children: [
        const SizedBox(height: 96),
        Icon(Icons.schedule, size: 64, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No scheduled actions yet',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Use the + button to set up a reminder or recurring check-in.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

void _showCreateDialog(BuildContext context) {
  final provider = context.read<ScheduledActionsProvider>();
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ScheduledActionEditor(
      onSubmit:
          ({
            required String prompt,
            String? title,
            String? cronExpr,
            DateTime? runAt,
            String? systemPrompt,
          }) async {
            final created = await provider.create(
              prompt: prompt,
              title: title,
              cronExpr: cronExpr,
              runAt: runAt,
              systemPrompt: systemPrompt,
            );
            return created != null;
          },
    ),
  );
}

void _showEditDialog(BuildContext context, ScheduledAction action) {
  final provider = context.read<ScheduledActionsProvider>();
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ScheduledActionEditor(
      existing: action,
      onSubmit:
          ({
            required String prompt,
            String? title,
            String? cronExpr,
            DateTime? runAt,
            String? systemPrompt,
          }) {
            return provider.update(
              action.id,
              prompt: prompt,
              // Empty string (not null) so clearing the title sticks.
              title: title ?? '',
              cronExpr: cronExpr,
              runAt: runAt,
              systemPrompt: systemPrompt,
            );
          },
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final ScheduledAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<ScheduledActionsProvider>();

    final subtitleParts = <String>[];
    if (action.isRecurring) {
      subtitleParts.add('Cron: ${action.cronExpr}');
    } else if (action.runAt != null) {
      subtitleParts.add('At: ${_formatDateTime(action.runAt!.toLocal())}');
    }
    if (action.nextRun != null && action.isActive) {
      subtitleParts.add('Next: ${_formatDateTime(action.nextRun!.toLocal())}');
    }
    if (action.lastRunAt != null) {
      subtitleParts.add(
        'Last: ${_formatDateTime(action.lastRunAt!.toLocal())}'
        ' (${action.lastRunStatus ?? "?"})',
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ListTile(
        leading: Icon(
          action.isRecurring ? Icons.repeat : Icons.alarm,
          color: action.isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        title: Text(
          action.title?.isNotEmpty == true ? action.title! : action.prompt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (subtitleParts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitleParts.join(' • '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: action.isActive,
              onChanged: (value) => provider.setActive(action.id, value),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: AppLocalizations.of(context)!.tooltipEdit,
              onPressed: () => _showEditDialog(context, action),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: AppLocalizations.of(context)!.delete,
              onPressed: () => _confirmDelete(context, action),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ScheduledAction action,
  ) async {
    final provider = context.read<ScheduledActionsProvider>();
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.titleDeleteScheduledAction),
        content: Text(
          'Remove "${action.title ?? action.prompt}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.delete(action.id);
    }
  }
}

typedef _SubmitFn =
    Future<bool> Function({
      required String prompt,
      String? title,
      String? cronExpr,
      DateTime? runAt,
      String? systemPrompt,
    });

class _ScheduledActionEditor extends StatefulWidget {
  const _ScheduledActionEditor({required this.onSubmit, this.existing});

  final _SubmitFn onSubmit;

  /// When set, the form is pre-filled from this action and submits an edit.
  final ScheduledAction? existing;

  @override
  State<_ScheduledActionEditor> createState() => _ScheduledActionEditorState();
}

class _ScheduledActionEditorState extends State<_ScheduledActionEditor> {
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _cronController = TextEditingController(text: '0 9 * * *');
  DateTime? _runAt;
  bool _submitting = false;
  _Mode _mode = _Mode.recurring;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      _titleController.text = a.title ?? '';
      _promptController.text = a.prompt;
      if (a.isRecurring) {
        _cronController.text = a.cronExpr!;
      } else {
        _mode = _Mode.oneOff;
        _runAt = a.runAt?.toLocal();
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    _cronController.dispose();
    super.dispose();
  }

  Future<void> _pickRunAt() async {
    final now = DateTime.now();
    // An edited action's run time may be in the past; clamp so the picker's
    // initialDate never precedes firstDate.
    final initial = _runAt != null && _runAt!.isAfter(now)
        ? _runAt!
        : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _runAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null) return;
    setState(() {
      _runAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    String? cronExpr;
    DateTime? runAt;
    if (_mode == _Mode.recurring) {
      cronExpr = _cronController.text.trim();
      if (cronExpr.isEmpty) return;
    } else {
      runAt = _runAt;
      if (runAt == null) return;
    }

    setState(() => _submitting = true);
    final ok = await widget.onSubmit(
      prompt: prompt,
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      cronExpr: cronExpr,
      runAt: runAt,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'New scheduled action'
            : 'Edit scheduled action',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelTitleOptional,
                  hintText: 'e.g. "Morning standup"',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _promptController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelPrompt,
                  hintText: AppLocalizations.of(
                    context,
                  )!.hintWhatShouldTheAssistantDo,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SegmentedButton<_Mode>(
                segments: [
                  ButtonSegment(
                    value: _Mode.recurring,
                    label: Text(AppLocalizations.of(context)!.labelRecurring),
                    icon: Icon(Icons.repeat),
                  ),
                  ButtonSegment(
                    value: _Mode.oneOff,
                    label: Text(AppLocalizations.of(context)!.labelOneOff),
                    icon: Icon(Icons.alarm),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 12),
              if (_mode == _Mode.recurring)
                TextField(
                  controller: _cronController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.labelCronExpression,
                    hintText: 'e.g. "0 9 * * mon-fri"',
                    helperText: 'min hour day month weekday',
                  ),
                )
              else
                InkWell(
                  onTap: _pickRunAt,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.labelRunAt,
                      suffixIcon: Icon(Icons.event),
                    ),
                    child: Text(
                      _runAt == null
                          ? 'Pick a date and time'
                          : _formatDateTime(_runAt!),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

enum _Mode { recurring, oneOff }

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
