import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/usage/models/usage_summary.dart';
import 'package:garbanzo_ai/features/usage/providers/usage_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class UsagePage extends StatelessWidget {
  const UsagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UsageProvider()..load(),
      child: const _UsageView(),
    );
  }
}

class _UsageView extends StatelessWidget {
  const _UsageView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<UsageProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.titleTokenUsage),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: 'Time range',
            onSelected: (value) => provider.load(days: value),
            initialValue: provider.days,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 7,
                child: Text(AppLocalizations.of(context)!.last7Days),
              ),
              PopupMenuItem(
                value: 30,
                child: Text(AppLocalizations.of(context)!.last30Days),
              ),
              PopupMenuItem(
                value: 90,
                child: Text(AppLocalizations.of(context)!.last90Days),
              ),
              PopupMenuItem(
                value: 365,
                child: Text(AppLocalizations.of(context)!.last12Months),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context)!.tooltipRefresh,
            onPressed: provider.isLoading ? null : () => provider.load(),
          ),
        ],
      ),
      body: Builder(
        builder: (_) {
          if (provider.isLoading && provider.summary == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null && provider.summary == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(provider.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => provider.load(),
                      child: Text(AppLocalizations.of(context)!.labelRetry),
                    ),
                  ],
                ),
              ),
            );
          }
          final summary = provider.summary;
          if (summary == null || summary.totalMessages == 0) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bar_chart,
                      size: 72,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No usage in the last ${provider.days} days',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start a conversation to see your token consumption here.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => provider.load(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TotalsRow(summary: summary),
                const SizedBox(height: 24),
                _SectionTitle('Daily tokens (${summary.days} days)'),
                const SizedBox(height: 8),
                _DailyChart(summary: summary),
                const SizedBox(height: 24),
                _SectionTitle('By model'),
                const SizedBox(height: 8),
                _ByModelSection(summary: summary),
                const SizedBox(height: 24),
                _SectionTitle('Top conversations'),
                const SizedBox(height: 8),
                _ByConversationSection(summary: summary),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.summary});
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _StatCard(
            label: 'Total tokens',
            value: _formatNumber(summary.totalTokens),
            icon: Icons.token_outlined,
          ),
          _StatCard(
            label: AppLocalizations.of(context)!.labelPrompt,
            value: _formatNumber(summary.totalTokensPrompt),
            icon: Icons.arrow_upward,
          ),
          _StatCard(
            label: 'Generated',
            value: _formatNumber(summary.totalTokensGenerated),
            icon: Icons.arrow_downward,
          ),
          _StatCard(
            label: AppLocalizations.of(context)!.labelMessages,
            value: _formatNumber(summary.totalMessages),
            icon: Icons.chat_outlined,
          ),
        ];
        final narrow = constraints.maxWidth < 600;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (c) => SizedBox(
                  width: narrow
                      ? (constraints.maxWidth - 12) / 2
                      : (constraints.maxWidth - 36) / 4,
                  child: c,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.summary});
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = summary.byDay;
    if (points.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              AppLocalizations.of(context)!.noDailyData,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      );
    }

    double maxY = 0;
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final total = (p.tokensPrompt + p.tokensGenerated).toDouble();
      if (total > maxY) maxY = total;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: total,
              color: theme.colorScheme.primary,
              width: 14,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
              rodStackItems: [
                BarChartRodStackItem(
                  0,
                  p.tokensPrompt.toDouble(),
                  theme.colorScheme.primary.withValues(alpha: 0.55),
                ),
                BarChartRodStackItem(
                  p.tokensPrompt.toDouble(),
                  total,
                  theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 24, 24, 16),
        child: SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY == 0 ? 10 : maxY * 1.15,
              barGroups: groups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.max) return const SizedBox.shrink();
                      return Text(
                        _formatShortNumber(value.toInt()),
                        style: theme.textTheme.bodySmall,
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= points.length) {
                        return const SizedBox.shrink();
                      }
                      final step = (points.length / 6).ceil().clamp(1, 999);
                      if (idx % step != 0 && idx != points.length - 1) {
                        return const SizedBox.shrink();
                      }
                      final date = points[idx].date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${date.month}/${date.day}',
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  tooltipPadding: const EdgeInsets.all(8),
                  getTooltipItem: (group, _, rod, idx) {
                    final point = points[group.x];
                    return BarTooltipItem(
                      '${point.date.year}-${point.date.month.toString().padLeft(2, '0')}-${point.date.day.toString().padLeft(2, '0')}\n'
                      'Prompt: ${_formatNumber(point.tokensPrompt)}\n'
                      'Generated: ${_formatNumber(point.tokensGenerated)}',
                      TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ByModelSection extends StatelessWidget {
  const _ByModelSection({required this.summary});
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (summary.byModel.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxValue = summary.byModel
        .map((m) => m.totalTokens)
        .reduce((a, b) => a > b ? a : b);

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < summary.byModel.length; i++) ...[
            _ModelRow(entry: summary.byModel[i], maxValue: maxValue),
            if (i < summary.byModel.length - 1)
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.3),
              ),
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.entry, required this.maxValue});
  final UsageByModel entry;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = maxValue == 0 ? 0.0 : entry.totalTokens / maxValue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.model,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatNumber(entry.totalTokens),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatNumber(entry.tokensPrompt)} in · '
            '${_formatNumber(entry.tokensGenerated)} out · '
            '${entry.messageCount} msgs',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ByConversationSection extends StatelessWidget {
  const _ByConversationSection({required this.summary});
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (summary.byConversation.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < summary.byConversation.length; i++) ...[
            ListTile(
              title: Text(
                summary.byConversation[i].title ?? 'Untitled',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_formatNumber(summary.byConversation[i].tokensPrompt)} in · '
                '${_formatNumber(summary.byConversation[i].tokensGenerated)} out',
                style: theme.textTheme.bodySmall,
              ),
              trailing: Text(
                _formatNumber(summary.byConversation[i].totalTokens),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              dense: true,
            ),
            if (i < summary.byConversation.length - 1)
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.3),
              ),
          ],
        ],
      ),
    );
  }
}

String _formatNumber(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _formatShortNumber(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return value.toString();
}
