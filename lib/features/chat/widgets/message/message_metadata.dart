import 'package:flutter/material.dart';

/// Compact icon button to toggle metadata visibility.
class MetadataIconToggle extends StatelessWidget {
  const MetadataIconToggle({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.colorScheme,
  });

  final bool isExpanded;
  final VoidCallback onToggle;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isExpanded ? Icons.info : Icons.info_outline,
              size: 14,
              color: isExpanded
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              isExpanded ? 'Hide' : 'Info',
              style: TextStyle(
                fontSize: 12,
                color: isExpanded
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded metadata details shown below the action row.
class MetadataDetails extends StatelessWidget {
  const MetadataDetails({
    super.key,
    required this.metadata,
    required this.colorScheme,
    required this.textTheme,
  });

  final Map<String, dynamic> metadata;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // Support both backend field names (tokens_prompt, tokens_generated, total_duration_ns)
    // and legacy field names (input_tokens, output_tokens, response_time_ms)
    final inputTokens = metadata['tokens_prompt'] ?? metadata['input_tokens'];
    final outputTokens = metadata['tokens_generated'] ?? metadata['output_tokens'];
    final totalDurationNs = metadata['total_duration_ns'];
    final responseTimeMs = metadata['response_time_ms'];
    final totalTokens = metadata['total_tokens'] ??
        ((inputTokens != null && outputTokens != null)
            ? (inputTokens as num) + (outputTokens as num)
            : null);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          if (inputTokens != null)
            MetadataItem(
              icon: Icons.input,
              label: 'In',
              value: _formatNumber(inputTokens),
              colorScheme: colorScheme,
            ),
          if (outputTokens != null)
            MetadataItem(
              icon: Icons.output,
              label: 'Out',
              value: _formatNumber(outputTokens),
              colorScheme: colorScheme,
            ),
          if (totalTokens != null)
            MetadataItem(
              icon: Icons.token,
              label: 'Total',
              value: _formatNumber(totalTokens),
              colorScheme: colorScheme,
            ),
          if (responseTimeMs != null)
            MetadataItem(
              icon: Icons.timer_outlined,
              label: 'Time',
              value: _formatDuration(responseTimeMs),
              colorScheme: colorScheme,
            ),
          if (totalDurationNs != null)
            MetadataItem(
              icon: Icons.timer_outlined,
              label: 'Time',
              value: _formatNanoseconds(totalDurationNs),
              colorScheme: colorScheme,
            ),
        ],
      ),
    );
  }

  String _formatNumber(dynamic value) {
    if (value is int) return value.toString();
    if (value is double) return value.toStringAsFixed(0);
    return value.toString();
  }

  String _formatDuration(dynamic value) {
    double ms;
    if (value is int) {
      ms = value.toDouble();
    } else if (value is double) {
      ms = value;
    } else {
      return value.toString();
    }

    if (ms < 1000) return '${ms.toStringAsFixed(0)}ms';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(1)}m';
  }

  String _formatNanoseconds(dynamic value) {
    double ns;
    if (value is int) {
      ns = value.toDouble();
    } else if (value is double) {
      ns = value;
    } else {
      return value.toString();
    }

    final ms = ns / 1000000;
    return _formatDuration(ms);
  }
}

/// A single metadata item displayed inline (icon + label + value).
class MetadataItem extends StatelessWidget {
  const MetadataItem({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 4),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
