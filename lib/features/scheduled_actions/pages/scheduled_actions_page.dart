import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/scheduled_actions/models/scheduled_action.dart';
import 'package:garbanzo_ai/features/scheduled_actions/providers/scheduled_actions_provider.dart';

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
        title: const Text('Scheduled actions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: provider.loading ? null : provider.load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New'),
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
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
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
        title: const Text('Delete scheduled action'),
        content: Text(
          'Remove "${action.title ?? action.prompt}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
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
  const _ScheduledActionEditor({required this.onSubmit});

  final _SubmitFn onSubmit;

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
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    _cronController.dispose();
    super.dispose();
  }

  Future<void> _pickRunAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _runAt ?? now.add(const Duration(hours: 1)),
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
      title: const Text('New scheduled action'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'e.g. "Morning standup"',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _promptController,
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  hintText: 'What should the assistant do?',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(
                    value: _Mode.recurring,
                    label: Text('Recurring'),
                    icon: Icon(Icons.repeat),
                  ),
                  ButtonSegment(
                    value: _Mode.oneOff,
                    label: Text('One-off'),
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
                  decoration: const InputDecoration(
                    labelText: 'Cron expression',
                    hintText: 'e.g. "0 9 * * mon-fri"',
                    helperText: 'min hour day month weekday',
                  ),
                )
              else
                InkWell(
                  onTap: _pickRunAt,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Run at',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
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
