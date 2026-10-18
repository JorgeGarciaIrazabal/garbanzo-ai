import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

typedef VisualSubmit =
    Future<void> Function(String action, Map<String, dynamic> values);

/// Catalog builders are intentionally small native widgets, with no model code
/// execution, dynamic routes, or second chat state-management system.
Widget buildVisualComponent(
  CatalogItemContext item, {
  required VisualSubmit onSubmit,
  required bool canSubmit,
  required Map<String, Map<String, dynamic>> statuses,
  required Set<String> inFlight,
}) {
  final data = Map<String, dynamic>.from(item.data as Map);
  final context = item.buildContext;
  final theme = Theme.of(context);
  final children = (data['children'] as List? ?? [])
      .cast<String>()
      .map((id) => item.buildChild(id))
      .toList();
  switch (item.type) {
    case 'Column':
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: children,
      );
    case 'Row':
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 560
              ? 1
              : children.length.clamp(1, 3);
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: children
                .map((child) => SizedBox(width: width, child: child))
                .toList(),
          );
        },
      );
    case 'Card':
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              if (data['title'] != null)
                Text(
                  data['title'] as String,
                  style: theme.textTheme.titleMedium,
                ),
              ...children,
            ],
          ),
        ),
      );
    case 'Text':
      return SelectableText(data['text'] as String);
    case 'Metric':
      return Semantics(
        label: '${data['label']}: ${data['value']}',
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['label'] as String,
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  data['value'] as String,
                  style: theme.textTheme.headlineMedium,
                ),
                if (data['detail'] != null) Text(data['detail'] as String),
              ],
            ),
          ),
        ),
      );
    case 'Table':
      return VisualTable(data: data);
    case 'Chart':
      return VisualChart(data: data);
    case 'Timeline':
      return Column(
        children: [
          for (final (index, entry) in (data['items'] as List).indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 16, child: Text('${index + 1}')),
              title: Text(entry['title'] as String),
              subtitle: entry['detail'] == null
                  ? null
                  : Text(entry['detail'] as String),
            ),
        ],
      );
    case 'Checklist':
      return _VisualChecklist(items: (data['items'] as List).cast<Map>());
    case 'Form':
    case 'Choices':
      final action = data['action'] as String;
      return VisualForm(
        data: data,
        status: statuses[action],
        enabled: canSubmit && !inFlight.contains(action),
        busy: inFlight.contains(action),
        onSubmit: (values) => onSubmit(action, values),
      );
    default:
      throw FormatException('Unsupported visual component: ${item.type}');
  }
}

class VisualTable extends StatefulWidget {
  const VisualTable({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<VisualTable> createState() => _VisualTableState();
}

class _VisualTableState extends State<VisualTable> {
  String _filter = '';
  int? _sortColumn;
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final columns = (widget.data['columns'] as List).cast<String>();
    final rows = (widget.data['rows'] as List)
        .map((r) => List<Object?>.from(r as List))
        .where((r) => r.any((v) => '$v'.toLowerCase().contains(_filter)))
        .toList();
    if (_sortColumn case final int index) {
      rows.sort((a, b) {
        final left = a[index], right = b[index];
        final comparison = left is num && right is num
            ? left.compareTo(right)
            : '${left ?? ''}'.compareTo('${right ?? ''}');
        return _ascending ? comparison : -comparison;
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.visualFilter,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _filter = value.toLowerCase()),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: _sortColumn,
            sortAscending: _ascending,
            dataRowMaxHeight: 100,
            columns: [
              for (final (index, label) in columns.indexed)
                DataColumn(
                  label: Text(label),
                  onSort: (_, ascending) => setState(() {
                    _sortColumn = index;
                    _ascending = ascending;
                  }),
                ),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    for (final value in row)
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text('${value ?? ''}'),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class VisualChart extends StatefulWidget {
  const VisualChart({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<VisualChart> createState() => _VisualChartState();
}

class _VisualChartState extends State<VisualChart> {
  final _hidden = <int>{};

  @override
  Widget build(BuildContext context) {
    final labels = (widget.data['labels'] as List).cast<String>();
    final series = (widget.data['series'] as List).cast<Map>();
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      Colors.orange,
      Colors.teal,
      Colors.pink,
    ];
    final visible = series.indexed
        .where((s) => !_hidden.contains(s.$1))
        .toList();
    final title = widget.data['title'] as String?;
    final titles = FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          interval: (labels.length / 6).ceil().clamp(1, 100).toDouble(),
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 ||
                index >= labels.length ||
                value != index.toDouble()) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 64,
                child: Text(
                  labels[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            );
          },
        ),
      ),
    );
    Widget chart;
    if (visible.isEmpty ||
        (widget.data['kind'] == 'pie' &&
            (series.first['values'] as List).every((v) => v == 0))) {
      chart = Center(
        child: Text(AppLocalizations.of(context)!.visualNoChartData),
      );
    } else if (widget.data['kind'] == 'line') {
      chart = LineChart(
        LineChartData(
          titlesData: titles,
          lineBarsData: [
            for (final (index, entry) in visible)
              LineChartBarData(
                color: colors[index % colors.length],
                spots: [
                  for (final (x, value) in (entry['values'] as List).indexed)
                    FlSpot(x.toDouble(), (value as num).toDouble()),
                ],
                isCurved: false,
                dotData: FlDotData(show: labels.length <= 20),
              ),
          ],
        ),
      );
    } else if (widget.data['kind'] == 'bar') {
      chart = BarChart(
        BarChartData(
          titlesData: titles,
          barGroups: [
            for (var x = 0; x < labels.length; x++)
              BarChartGroupData(
                x: x,
                barRods: [
                  for (final (index, entry) in visible)
                    BarChartRodData(
                      toY: ((entry['values'] as List)[x] as num).toDouble(),
                      color: colors[index % colors.length],
                      width: (160 / labels.length / visible.length)
                          .clamp(2, 16)
                          .toDouble(),
                    ),
                ],
              ),
          ],
        ),
      );
    } else {
      chart = PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 32,
          sections: [
            for (final (index, value)
                in (series.first['values'] as List).indexed)
              PieChartSectionData(
                value: (value as num).toDouble(),
                title: '${labels[index]}\n$value',
                color: colors[index % colors.length],
                radius: 76,
                titleStyle: TextStyle(color: scheme.onPrimary, fontSize: 11),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Text(
          title ?? series.first['label'] as String,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (series.length > 1)
          Wrap(
            spacing: 8,
            children: [
              for (final (index, entry) in series.indexed)
                FilterChip(
                  label: Text(entry['label'] as String),
                  avatar: Icon(
                    Icons.circle,
                    color: colors[index % colors.length],
                    size: 12,
                  ),
                  selected: !_hidden.contains(index),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _hidden.remove(index);
                    } else {
                      _hidden.add(index);
                    }
                  }),
                ),
            ],
          ),
        Semantics(
          label: [
            ?title,
            for (final entry in series) '${entry['label']}: ${entry['values']}',
          ].join('. '),
          child: SizedBox(height: 260, child: chart),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(AppLocalizations.of(context)!.visualShowData),
          children: [
            VisualTable(
              data: {
                'columns': ['', for (final s in series) s['label']],
                'rows': [
                  for (var i = 0; i < labels.length; i++)
                    [
                      labels[i],
                      for (final s in series) (s['values'] as List)[i],
                    ],
                ],
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _VisualChecklist extends StatefulWidget {
  const _VisualChecklist({required this.items});
  final List<Map> items;
  @override
  State<_VisualChecklist> createState() => _VisualChecklistState();
}

class _VisualChecklistState extends State<_VisualChecklist> {
  late final _checked = [for (final i in widget.items) i['checked'] == true];
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, item) in widget.items.indexed)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(item['label'] as String),
          value: _checked[index],
          onChanged: (value) => setState(() => _checked[index] = value!),
        ),
    ],
  );
}

class VisualForm extends StatefulWidget {
  const VisualForm({
    super.key,
    required this.data,
    required this.status,
    required this.enabled,
    required this.busy,
    required this.onSubmit,
  });
  final Map<String, dynamic> data;
  final Map<String, dynamic>? status;
  final bool enabled;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  @override
  State<VisualForm> createState() => _VisualFormState();
}

class _VisualFormState extends State<VisualForm> {
  final _key = GlobalKey<FormState>();
  late final Map<String, dynamic> _values = {
    for (final f in widget.data['fields'] as List? ?? [])
      f['name'] as String: f['value'] ?? (f['type'] == 'checkbox' ? false : ''),
    ...?widget.status?['values'] as Map<String, dynamic>?,
  };

  @override
  void didUpdateWidget(VisualForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status && widget.status?['values'] is Map) {
      _values.addAll(
        Map<String, dynamic>.from(widget.status!['values'] as Map),
      );
    }
  }

  bool get _editable => widget.enabled && widget.status == null;

  String? _resultText() {
    final result = widget.status?['result'];
    if (result is! Map) return null;
    final detail =
        result['error'] ??
        result['content'] ??
        (result['memory'] is Map ? result['memory']['content'] : null) ??
        (result['action_data'] is Map
            ? result['action_data']['title']
            : null) ??
        result['name'];
    if (detail is String) return detail;
    if (detail is List) {
      final text = detail.whereType<String>().join('\n');
      return text.isEmpty ? null : text;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = widget.status?['status'];
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          for (final raw in widget.data['fields'] as List? ?? [])
            _field(Map<String, dynamic>.from(raw as Map)),
          if (widget.data['options'] case final List options)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  OutlinedButton(
                    onPressed: _editable
                        ? () => widget.onSubmit({'choice': option['value']})
                        : null,
                    child: Text(option['label'] as String),
                  ),
              ],
            )
          else
            FilledButton(
              onPressed: _editable
                  ? () {
                      if (_key.currentState!.validate()) {
                        widget.onSubmit(Map.of(_values));
                      }
                    }
                  : null,
              child: Text(widget.data['submitLabel'] as String),
            ),
          if (widget.busy) const LinearProgressIndicator(),
          if (status != null)
            Semantics(
              liveRegion: true,
              child: Text(switch (status) {
                'completed' => l10n.visualActionCompleted,
                'failed' =>
                  '${l10n.visualActionFailed}: ${_resultText() ?? ''}',
                _ => l10n.visualActionPending,
              }),
            ),
          if (status == 'completed' && _resultText() != null)
            SelectableText(_resultText()!),
        ],
      ),
    );
  }

  Widget _field(Map<String, dynamic> field) {
    final name = field['name'] as String;
    final label = field['label'] as String;
    final type = field['type'];
    final l10n = AppLocalizations.of(context)!;
    if (type == 'checkbox') {
      return FormField<bool>(
        validator: (_) => field['required'] == true && _values[name] != true
            ? l10n.visualRequired
            : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              value: _values[name] == true,
              onChanged: _editable
                  ? (value) => setState(() => _values[name] = value)
                  : null,
            ),
            if (state.errorText != null)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if (type == 'select') {
      final value = _values[name];
      final options = (field['options'] as List).cast<String>();
      if (options.isEmpty ||
          options.toSet().length != options.length ||
          (value != null &&
              value != '' &&
              (value is! String || !options.contains(value)))) {
        return Text(l10n.visualAnswerError);
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('$name-${widget.status?['submission_id']}'),
        initialValue: value == '' || value == null ? null : value as String,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: _editable
            ? (value) => setState(() => _values[name] = value)
            : null,
        validator: (value) => field['required'] == true && value == null
            ? l10n.visualRequired
            : null,
      );
    }
    return TextFormField(
      key: ValueKey('$name-${widget.status?['submission_id']}'),
      initialValue: '${_values[name] ?? ''}',
      enabled: _editable,
      maxLength: 2000,
      decoration: InputDecoration(
        labelText: label,
        hintText: type == 'date' ? 'YYYY-MM-DD' : null,
        counterText: '',
      ),
      keyboardType: type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : type == 'date'
          ? TextInputType.datetime
          : TextInputType.text,
      onChanged: (value) => _values[name] = type == 'number' && value.isNotEmpty
          ? num.tryParse(value) ?? value
          : value,
      validator: (value) {
        if (field['required'] == true &&
            (value == null || value.trim().isEmpty)) {
          return l10n.visualRequired;
        }
        if (value != null && value.isNotEmpty) {
          if (type == 'number' && (num.tryParse(value)?.isFinite != true)) {
            return l10n.visualInvalidNumber;
          }
          if (type == 'date' &&
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
            return l10n.visualInvalidDate;
          }
        }
        return null;
      },
    );
  }
}
