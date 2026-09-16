import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/motion.dart';
import 'package:garbanzo_ai/features/chat/models/agent_progress.dart';
import 'package:garbanzo_ai/features/chat/widgets/progress/agent_progress_labels.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// One observed action on the agent's timeline.
///
/// Shows what was touched, what kind of action it was, how long it took, and
/// whether it succeeded — with a connector rail so the sequence reads as a
/// timeline rather than a list of unrelated rows.
class AgentStepRow extends StatelessWidget {
  const AgentStepRow({
    super.key,
    required this.step,
    required this.isLast,
    required this.live,
  });

  final AgentStep step;
  final bool isLast;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final running = live && step.isRunning;
    final failed = step.failed;
    final accent = failed
        ? colors.error
        : running
        ? colors.primary
        : colors.onSurfaceVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(colors, running, failed, accent),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 4 : 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _kindIcon(colors, accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: Motion.fast,
                          style:
                              theme.textTheme.bodyMedium?.copyWith(
                                color: failed ? colors.error : colors.onSurface,
                                fontWeight: running
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ) ??
                              const TextStyle(),
                          child: Text(
                            agentStepRowLabel(step, l10n, live: live),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (step.durationMs != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            agentDurationLabel(
                              (step.durationMs! / 1000).round(),
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.8,
                              ),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (step.resultPreview != null) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Text(
                        step.resultPreview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Timeline rail: a status node plus a connector down to the next step.
  Widget _rail(ColorScheme colors, bool running, bool failed, Color accent) {
    return SizedBox(
      width: 18,
      child: Column(
        children: [
          const SizedBox(height: 2),
          if (running)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.7, color: accent),
            )
          else
            Icon(
              failed ? Icons.close_rounded : Icons.check_rounded,
              size: 13,
              color: failed
                  ? colors.error
                  : colors.primary.withValues(alpha: 0.9),
            ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 1.5,
                margin: const EdgeInsets.symmetric(vertical: 3),
                color: colors.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kindIcon(ColorScheme colors, Color accent) {
    final icon = switch (step.phase) {
      AgentProgressPhase.reading => Icons.description_outlined,
      AgentProgressPhase.editing => Icons.edit_outlined,
      AgentProgressPhase.running => Icons.terminal_outlined,
      AgentProgressPhase.searching => Icons.search,
      AgentProgressPhase.building => Icons.auto_awesome_outlined,
      AgentProgressPhase.verifying => Icons.fact_check_outlined,
      AgentProgressPhase.thinking => Icons.psychology_outlined,
      AgentProgressPhase.starting => Icons.play_circle_outline,
      AgentProgressPhase.done => Icons.check_circle_outline,
      AgentProgressPhase.failed => Icons.error_outline,
      AgentProgressPhase.cancelled => Icons.stop_circle_outlined,
    };
    return Icon(icon, size: 14, color: accent.withValues(alpha: 0.85));
  }
}
