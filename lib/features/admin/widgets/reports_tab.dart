import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/reports/models/report.dart';
import 'package:garbanzo_ai/features/reports/services/reports_service.dart';

/// Admin triage tab for user-submitted bug/feature reports (idea 14).
///
/// Self-contained (unlike the AdminProvider-backed tabs) since its state is
/// just a filtered list; service calls are injectable for widget tests.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key, this.load, this.updateStatus});

  /// Defaults to [ReportsService.adminList] / [ReportsService.adminUpdateStatus].
  final Future<List<Report>> Function({String? status})? load;
  final Future<Report> Function(String id, String status)? updateStatus;

  static const statusLabels = {
    'open': 'Open',
    'in_progress': 'In progress',
    'closed': 'Closed',
  };

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  List<Report> _reports = [];
  bool _loading = true;
  String? _error;

  /// Selected status filter; null shows everything.
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await (widget.load ?? ReportsService.instance.adminList)(
        status: _filter,
      );
      if (mounted) {
        setState(() {
          _reports = reports;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setStatus(Report report, String status) async {
    try {
      final updated =
          await (widget.updateStatus ??
              ReportsService.instance.adminUpdateStatus)(report.id, status);
      if (!mounted) return;
      setState(() {
        final i = _reports.indexWhere((r) => r.id == report.id);
        if (i == -1) return;
        // Under a status filter the updated report no longer matches it.
        if (_filter != null && updated.status != _filter) {
          _reports.removeAt(i);
        } else {
          _reports[i] = updated;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget body;
    if (_loading && _reports.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _reports.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_reports.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.feedback_outlined, color: scheme.outline, size: 48),
            const SizedBox(height: 8),
            Text(
              _filter == null
                  ? 'No reports yet'
                  : 'No ${ReportsTab.statusLabels[_filter]!.toLowerCase()} reports',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _reports.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _ReportTile(
            report: _reports[i],
            onSetStatus: (status) => _setStatus(_reports[i], status),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<String>(
            key: const ValueKey('reports_status_filter'),
            segments: [
              const ButtonSegment(value: 'all', label: Text('All')),
              for (final e in ReportsTab.statusLabels.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_filter ?? 'all'},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              _filter = selection.first == 'all' ? null : selection.first;
              _load();
            },
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// One report row: type icon, title, submitter + date, expandable
/// description, and a status menu for triage.
class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, required this.onSetStatus});

  final Report report;
  final void Function(String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isBug = report.type == 'bug';
    final statusColor = switch (report.status) {
      'open' => scheme.error,
      'in_progress' => scheme.tertiary,
      _ => scheme.outline,
    };
    final date = report.createdAt.toLocal().toString().split(' ').first;

    return ExpansionTile(
      key: ValueKey('report_tile_${report.id}'),
      leading: Icon(
        isBug ? Icons.bug_report_outlined : Icons.lightbulb_outline,
        color: isBug ? scheme.error : scheme.tertiary,
      ),
      title: Text(report.title),
      subtitle: Text(
        '${report.userId} · $date',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('report_status_menu_${report.id}'),
        tooltip: 'Set status',
        initialValue: report.status,
        onSelected: onSetStatus,
        itemBuilder: (context) => [
          for (final e in ReportsTab.statusLabels.entries)
            PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: Chip(
          label: Text(
            ReportsTab.statusLabels[report.status] ?? report.status,
            style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
          ),
          side: BorderSide(color: statusColor),
          visualDensity: VisualDensity.compact,
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [SelectableText(report.description)],
    );
  }
}
