import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/widgets/visual_answers/visual_layout.dart';

class VisualKeyValue extends StatelessWidget {
  const VisualKeyValue({super.key, required this.items});
  final List<Map> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, item) in items.indexed) ...[
        if (index > 0) const Divider(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final label = Text(
              item['label'] as String,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
            final value = SelectableText(item['value'] as String);
            if (constraints.maxWidth <
                MediaQuery.textScalerOf(context).scale(320)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [label, value],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                Expanded(child: label),
                Expanded(flex: 2, child: value),
              ],
            );
          },
        ),
      ],
    ],
  );
}

class VisualComparison extends StatelessWidget {
  const VisualComparison({super.key, required this.items});
  final List<Map> items;

  @override
  Widget build(BuildContext context) => VisualGrid(
    children: [
      for (final item in items)
        VisualPanel(
          highlighted: item['highlighted'] == true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              if (item['badge'] case final String badge)
                Text(badge, style: Theme.of(context).textTheme.labelLarge),
              Text(
                item['title'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (item['subtitle'] case final String subtitle) Text(subtitle),
              VisualKeyValue(items: (item['attributes'] as List).cast<Map>()),
            ],
          ),
        ),
    ],
  );
}

class VisualCallout extends StatelessWidget {
  const VisualCallout({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (data['tone']) {
      'success' => (Icons.check_circle_outline, scheme.primary),
      'warning' => (Icons.warning_amber_rounded, scheme.tertiary),
      _ => (Icons.info_outline, scheme.secondary),
    };
    return VisualPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Icon(icon, color: color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                if (data['title'] case final String title)
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                SelectableText(data['text'] as String),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VisualProgress extends StatelessWidget {
  const VisualProgress({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final value = (data['value'] as num).toDouble();
    return VisualPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            data['label'] as String,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${value.round()}%',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          LinearProgressIndicator(
            value: value / 100,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            semanticsLabel: data['label'] as String,
            semanticsValue: '${value.round()}%',
          ),
          if (data['detail'] case final String detail) Text(detail),
        ],
      ),
    );
  }
}

class VisualAccordion extends StatelessWidget {
  const VisualAccordion({super.key, required this.items});
  final List<Map> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in items)
        ExpansionTile(
          title: Text(item['title'] as String),
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [SelectableText(item['text'] as String)],
        ),
    ],
  );
}
