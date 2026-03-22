import 'package:flutter/material.dart';

/// Thin progress bar showing context window token usage.
///
/// Color-coded: primary < 60%, amber 60–80%, error > 80%.
class ContextWindowIndicator extends StatelessWidget {
  const ContextWindowIndicator({
    super.key,
    required this.tokensUsed,
    required this.contextLength,
  });

  final int tokensUsed;
  final int contextLength;

  @override
  Widget build(BuildContext context) {
    final ratio = (tokensUsed / contextLength).clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;

    final Color barColor;
    if (ratio > 0.8) {
      barColor = colorScheme.error;
    } else if (ratio > 0.6) {
      barColor = Colors.amber;
    } else {
      barColor = colorScheme.primary;
    }

    final pct = (ratio * 100).toStringAsFixed(0);
    final label = '$tokensUsed / $contextLength tokens ($pct%)';

    return Tooltip(
      message: label,
      child: LinearProgressIndicator(
        value: ratio,
        backgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        valueColor: AlwaysStoppedAnimation<Color>(barColor),
        minHeight: 3,
      ),
    );
  }
}
