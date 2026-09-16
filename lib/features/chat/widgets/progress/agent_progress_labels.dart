import 'package:garbanzo_ai/features/chat/models/agent_progress.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// The headline for the collapsed agent progress object.
///
/// Reads as a sentence about *work*, not about tooling: "Editing parser.dart",
/// "Running pytest -q". The label is grounded in what the agent actually did
/// (opencode's own title, or the command/file it passed), so it cannot drift
/// into a claim the run never made.
///
/// When the run is over this still describes the last thing that happened
/// rather than announcing a bare status: a "Finished" line sitting directly
/// above the list of steps reads as if it were itself a step, and it replaces
/// the one piece of information the collapsed card exists to convey. Terminal
/// status belongs in the meta line and the status glyph; the headline keeps
/// naming the work. Failures and cancellations are the exception — those are
/// noteworthy enough to lead with, with the steps below showing what led there.
String agentStepHeadline(
  AgentStep? step,
  AppLocalizations l10n, {
  String? activity,
  required bool live,
  required bool failed,
  required bool cancelled,
}) {
  if (!live) {
    if (cancelled) return l10n.agentProgressCancelled;
    if (failed) return l10n.agentProgressFailed;
    // Fall through: a completed run still names its last action.
  }

  final label = (step?.label != null && step!.label!.isNotEmpty)
      ? step.label
      : activity;

  if (step == null) {
    // No step yet: the run is alive (heartbeats) but has not touched anything.
    if (label != null && label.isNotEmpty) {
      return l10n.agentProgressRunning(label);
    }
    return l10n.agentProgressStarting;
  }

  return switch (step.phase) {
    AgentProgressPhase.reading =>
      label == null
          ? l10n.agentProgressReadingGeneric
          : l10n.agentProgressReading(label),
    AgentProgressPhase.editing =>
      label == null
          ? l10n.agentProgressEditingGeneric
          : l10n.agentProgressEditing(label),
    AgentProgressPhase.searching =>
      label == null
          ? l10n.agentProgressSearchingGeneric
          : l10n.agentProgressSearching(label),
    AgentProgressPhase.building =>
      label == null
          ? l10n.agentProgressBuildingGeneric
          : l10n.agentProgressBuilding(label),
    AgentProgressPhase.verifying => l10n.agentProgressVerifying,
    AgentProgressPhase.running =>
      label == null
          ? l10n.agentProgressRunningGeneric
          : l10n.agentProgressRunning(label),
    AgentProgressPhase.thinking => l10n.agentProgressThinking,
    AgentProgressPhase.starting => l10n.agentProgressStarting,
    AgentProgressPhase.done => l10n.agentProgressDone,
    AgentProgressPhase.failed => l10n.agentProgressFailed,
    AgentProgressPhase.cancelled => l10n.agentProgressCancelled,
  };
}

/// The per-row label inside the expanded history.
///
/// One line per observed action, phrased the same way as the headline so the
/// expanded view reads as the history that produced the collapsed summary.
String agentStepRowLabel(
  AgentStep step,
  AppLocalizations l10n, {
  required bool live,
}) => agentStepHeadline(
  step,
  l10n,
  live: live || step.isRunning,
  failed: step.failed,
  cancelled: false,
);

/// Human duration for a step or a run: "12s", "3m 4s".
String agentDurationLabel(int seconds) {
  if (seconds < 1) return '<1s';
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
  final hours = minutes ~/ 60;
  return '${hours}h ${minutes % 60}m';
}
