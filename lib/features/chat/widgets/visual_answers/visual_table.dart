import 'package:flutter/material.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

import 'package:garbanzo_ai/features/chat/widgets/visual_answers/visual_details.dart';
import 'package:garbanzo_ai/features/chat/widgets/visual_answers/visual_layout.dart';

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
  int _limit = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final columns = (widget.data['columns'] as List).cast<String>();
    final rows = (widget.data['rows'] as List)
        .map((r) => List<Object?>.from(r as List))
        .where(
          (r) => r.any((v) => '${v ?? ''}'.toLowerCase().contains(_filter)),
        )
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
    final visible = rows.take(_limit);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < MediaQuery.textScalerOf(context).scale(600);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: l10n.visualFilter,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _filter = value.toLowerCase();
                _limit = 10;
              }),
            ),
            if (compact && rows.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _sortColumn,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.visualSortBy),
                      items: [
                        for (final (index, label) in columns.indexed)
                          DropdownMenuItem(value: index, child: Text(label)),
                      ],
                      onChanged: (index) => setState(() => _sortColumn = index),
                    ),
                  ),
                  IconButton(
                    tooltip: _ascending
                        ? l10n.visualDescending
                        : l10n.visualAscending,
                    onPressed: _sortColumn == null
                        ? null
                        : () => setState(() => _ascending = !_ascending),
                    icon: Icon(
                      _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    ),
                  ),
                ],
              ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.visualNoRows),
              )
            else if (compact)
              for (final row in visible)
                VisualPanel(
                  child: VisualKeyValue(
                    items: [
                      for (var i = 0; i < columns.length; i++)
                        {'label': columns[i], 'value': '${row[i] ?? ''}'},
                    ],
                  ),
                )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: _sortColumn,
                  sortAscending: _ascending,
                  dataRowMaxHeight: double.infinity,
                  columns: [
                    for (final (index, label) in columns.indexed)
                      DataColumn(
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(label),
                        ),
                        onSort: (_, ascending) => setState(() {
                          _sortColumn = index;
                          _ascending = ascending;
                        }),
                      ),
                  ],
                  rows: [
                    for (final row in visible)
                      DataRow(
                        cells: [
                          for (final value in row)
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 240,
                                ),
                                child: Text('${value ?? ''}'),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            if (rows.length > _limit)
              TextButton.icon(
                onPressed: () => setState(() => _limit += 10),
                icon: const Icon(Icons.expand_more),
                label: Text(l10n.visualMoreRows),
              ),
          ],
        );
      },
    );
  }
}
