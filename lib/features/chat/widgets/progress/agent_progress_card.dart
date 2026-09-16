import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/motion.dart';
import 'package:garbanzo_ai/features/chat/models/agent_progress.dart';
import 'package:garbanzo_ai/features/chat/widgets/progress/agent_progress_labels.dart';
import 'package:garbanzo_ai/features/chat/widgets/progress/agent_step_row.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// The agent progress object.
///
/// One surface, used by every agent run in the app — an in-chat turn's tool
/// activity and a delegated workflow both render from [AgentProgress], so they
/// cannot describe the same work differently.
///
/// Collapsed, it answers the only question that matters while work is in
/// flight: *what is it doing right now, and is it still alive?* — the current
/// action, a ticking elapsed time, and an honest indicator of how long since
/// the agent last reported anything. Expanded, it becomes the full grounded
/// history: every step, its target, its duration, and its outcome.
///
/// Deliberately not a progress bar: a percentage would be invented. A list of
/// observed actions is not.
class AgentProgressCard extends StatefulWidget {
  const AgentProgressCard({
    super.key,
    required this.progress,
    this.onStop,
    this.onOpenDetails,
    this.dense = false,
    this.title,
  });

  final AgentProgress progress;

  /// Shown as a stop affordance while live. Null hides it (nothing to stop).
  final VoidCallback? onStop;

  /// Optional "view raw activity" escape hatch for the technical disclosure.
  final VoidCallback? onOpenDetails;

  /// Tighter layout for the in-chat rail, where vertical space is precious.
  final bool dense;

  /// Optional heading (e.g. the workflow's folder name).
  final String? title;

  @override
  State<AgentProgressCard> createState() => _AgentProgressCardState();
}

class _AgentProgressCardState extends State<AgentProgressCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Live runs open expanded so the user immediately sees the history rather
    // than a single line; finished runs stay collapsed, because by then the
    // last action IS the summary. Once the user toggles, their choice is kept
    // for the life of the widget (the stream rebuilds it constantly).
    _expanded = widget.progress.live && widget.progress.steps.length > 1;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(AgentProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.progress.live && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.progress.live && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final progress = widget.progress;
    final live = progress.live;
    final failed = progress.hasFailure;
    // A run is only genuinely "settled" when the stream says it is done AND no
    // step is still in flight. `live` can go false for reasons that say nothing
    // about the work (a stream hiccup, a client that reloaded mid-run), and
    // showing a success tick then would claim an outcome the run never reached.
    final settled = !live && !progress.hasRunningStep;
    final accent = failed
        ? colors.error
        : live
        ? colors.primary
        : colors.onSurfaceVariant.withValues(alpha: 0.8);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.dense ? 6 : 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (live ? accent : colors.outlineVariant).withValues(
              alpha: live ? 0.38 : 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, colors, l10n, accent, live, failed, settled),
            _animatedDetails(theme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _header(
    ThemeData theme,
    ColorScheme colors,
    AppLocalizations l10n,
    Color accent,
    bool live,
    bool failed,
    bool settled,
  ) {
    final progress = widget.progress;
    final current = progress.currentStep;
    final stepLabel = agentStepHeadline(
      current,
      l10n,
      activity: progress.heartbeatActivity,
      live: live,
      failed: failed,
      cancelled: false,
    );
    final meta = _metaLine(l10n, progress, accent);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('agent_progress_header'),
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            widget.dense ? 9 : 11,
            8,
            widget.dense ? 9 : 11,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusGlyph(
                live: live,
                failed: failed,
                settled: settled,
                accent: accent,
                pulse: _pulse,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.title != null) ...[
                      Text(
                        widget.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                    ],
                    AnimatedSwitcher(
                      duration: Motion.fast,
                      child: Text(
                        stepLabel,
                        key: ValueKey(stepLabel),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: failed ? colors.error : colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (live && widget.onStop != null)
                IconButton(
                  key: const ValueKey('agent_progress_stop'),
                  onPressed: widget.onStop,
                  tooltip: l10n.agentProgressStop,
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  color: colors.error,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: Motion.fast,
                child: Icon(
                  Icons.expand_more,
                  size: 19,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The second line: elapsed time, how many steps, how long since the agent
  /// last said anything, and — once the run is over — its outcome.
  ///
  /// The outcome belongs here rather than in the headline: the headline names
  /// the last action (that is what the collapsed card is for), and a separate
  /// "Finished" line above the steps reads as a step of its own.
  String _metaLine(
    AppLocalizations l10n,
    AgentProgress progress,
    Color accent,
  ) {
    final parts = <String>[];
    final elapsed = progress.elapsedLabel;
    if (progress.live && elapsed != null) {
      parts.add(l10n.agentProgressElapsed(elapsed));
    }
    final steps = progress.steps.length;
    if (steps > 0) {
      parts.add(l10n.agentProgressStepsSummary(steps));
    }
    if (progress.live) {
      final since = progress.secondsSinceSignal;
      if (since == null || since <= 5) {
        parts.add(l10n.agentProgressSignalNow);
      } else {
        parts.add(l10n.agentProgressLastSignal(_duration(since)));
      }
    } else {
      parts.add(
        progress.hasFailure ? l10n.agentProgressFailed : l10n.agentProgressDone,
      );
    }
    return parts.join(' · ');
  }

  Widget _animatedDetails(ThemeData theme, AppLocalizations l10n) {
    return ClipRect(
      child: AnimatedSize(
        duration: Motion.medium,
        curve: Motion.easeOut,
        alignment: Alignment.topCenter,
        child: !_expanded
            ? const SizedBox(width: double.infinity)
            : _steps(theme, l10n),
      ),
    );
  }

  Widget _steps(ThemeData theme, AppLocalizations l10n) {
    final colors = theme.colorScheme;
    final steps = widget.progress.steps;
    // History reads oldest-first, so the newest work appears at the bottom
    // next to the live header — the way a terminal or a log reads.
    final ordered = steps;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 6),
          if (ordered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l10n.agentProgressNoSteps,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < ordered.length; i++)
              AgentStepRow(
                step: ordered[i],
                isLast: i == ordered.length - 1,
                live: widget.progress.live,
              ),
          if (widget.progress.looksQuiet)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_empty,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.agentProgressQuiet(
                        _duration(widget.progress.secondsSinceSignal ?? 0),
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.onOpenDetails != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: widget.onOpenDetails,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                icon: const Icon(Icons.code, size: 15),
                label: Text(l10n.agentActivityTechnicalDetails),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact human duration: "8s", "3m 12s", "1h 4m".
String _duration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return '${minutes}m ${rest}s';
  final hours = minutes ~/ 60;
  return '${hours}h ${minutes % 60}m';
}

/// The leading status glyph: a pulsing pulse while live, a tick when done, a
/// cross when failed — and it keeps its slot so the row never jumps.
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({
    required this.live,
    required this.failed,
    required this.settled,
    required this.accent,
    required this.pulse,
  });

  final bool live;
  final bool failed;
  final bool settled;
  final Color accent;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = 30.0;

    if (!live) {
      // Not live, but steps are still unaccounted for: the run stopped being
      // reported on without any step confirming an outcome. Show a neutral
      // mark rather than a success tick — inventing a "done" here is the kind
      // of quiet lie the progress object exists to prevent.
      final (icon, tint) = switch ((failed, settled)) {
        (true, _) => (Icons.error_outline, colors.error),
        (false, true) => (Icons.check_rounded, colors.primary),
        (false, false) => (Icons.help_outline, colors.onSurfaceVariant),
      };
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 17, color: tint),
      );
    }

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(pulse.value);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1 + 0.08 * t),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: accent.withValues(alpha: 0.25 + 0.3 * t)),
          ),
          child: Center(
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: accent,
                value: null,
              ),
            ),
          ),
        );
      },
    );
  }
}
