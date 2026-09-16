import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_progress.freezed.dart';

/// Phases an agent run moves through, in the order a user would describe them.
///
/// Drives the label in the collapsed progress object: the user should learn
/// *what kind of work is happening* at a glance, without reading the log.
enum AgentProgressPhase {
  starting,
  thinking,
  reading,
  editing,
  running,
  searching,
  building,
  verifying,
  done,
  failed,
  cancelled,
}

/// One grounded step of an agent run.
///
/// Built from the tool-call/result messages the backend streams, so every step
/// corresponds to something that actually happened — never to model narration,
/// which can claim work that never occurred.
class AgentStep {
  const AgentStep({
    required this.id,
    required this.toolName,
    required this.phase,
    this.label,
    this.durationMs,
    this.started = false,
    this.done = false,
    this.failed = false,
    this.resultPreview,
  });

  /// Stable per-call id, so the same step updates in place instead of
  /// appending a duplicate on every streamed status change.
  final String id;
  final String toolName;
  final AgentProgressPhase phase;

  /// Human-readable target: opencode's own `title` when it provides one
  /// (a file path or the literal command), else a label derived from the
  /// tool input. Null means the step is known but not yet describable.
  final String? label;
  final int? durationMs;
  final bool started;

  /// Terminal and successful. While live, this is what tells the UI whether to
  /// render a spinner or a tick.
  final bool done;
  final bool failed;
  final String? resultPreview;

  bool get isRunning => started && !done && !failed;

  AgentStep copyWith({
    String? label,
    int? durationMs,
    bool? started,
    bool? done,
    bool? failed,
    String? resultPreview,
  }) => AgentStep(
    id: id,
    toolName: toolName,
    phase: phase,
    label: label ?? this.label,
    durationMs: durationMs ?? this.durationMs,
    started: started ?? this.started,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    resultPreview: resultPreview ?? this.resultPreview,
  );
}

/// The live progress of one agent run, derived from the stream.
///
/// This is the single model behind every agent-activity surface: a chat turn's
/// tool group and a delegated workflow's tile both render from it, so the two
/// cannot drift apart in how they describe the same work.
@freezed
abstract class AgentProgress with _$AgentProgress {
  const AgentProgress._();

  const factory AgentProgress({
    @Default(<AgentStep>[]) List<AgentStep> steps,
    @Default(false) bool live,

    /// Seconds since the run started, as last reported by a heartbeat. Null
    /// when no heartbeat has arrived yet (the client then falls back to its
    /// own clock from [startedAt]).
    int? heartbeatElapsedSeconds,

    /// Seconds since the last signal of any kind. The UI surfaces this so a
    /// quiet agent is visibly quiet rather than ambiguously idle.
    int? secondsSinceSignal,
    DateTime? startedAt,
    DateTime? finishedAt,

    /// Most recent activity reported by a heartbeat, used when no step is
    /// available yet (e.g. the model is still loading).
    String? heartbeatActivity,

    /// Steps completed, from the heartbeat. Distinct from `steps.length`
    /// because the stream may have been joined mid-run.
    @Default(0) int completedCount,
  }) = _AgentProgress;

  /// The step to show when collapsed: the most recent one that actually
  /// describes something. Older steps scroll away; only the newest matters.
  AgentStep? get currentStep {
    for (final step in steps.reversed) {
      if (step.label != null && step.label!.isNotEmpty) return step;
    }
    return steps.isEmpty ? null : steps.last;
  }

  bool get hasFailure => steps.any((step) => step.failed);

  /// True when at least one step never reported a terminal state.
  ///
  /// Used to avoid announcing an outcome the run has not actually reached: a
  /// client whose stream ends early would otherwise show a success tick over a
  /// step that is still, as far as anyone knows, in flight.
  bool get hasRunningStep => steps.any((step) => step.isRunning);

  /// True when the agent has produced nothing at all for a while. Long enough
  /// that it is worth telling the user, short enough to be honest about it.
  bool get looksQuiet => live && (secondsSinceSignal ?? 0) >= quietAfterSeconds;

  /// Human label for how long this run has been going.
  ///
  /// Prefers the backend's heartbeat (authoritative, and consistent for a
  /// client that joined mid-run) and falls back to the local clock.
  String? get elapsedLabel {
    final seconds = heartbeatElapsedSeconds ?? _localElapsedSeconds;
    if (seconds == null) return null;
    if (seconds < 1) return '<1s';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes < 60) return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
    final hours = minutes ~/ 60;
    return '${hours}h ${minutes % 60}m';
  }

  int? get _localElapsedSeconds {
    final start = startedAt;
    if (start == null) return null;
    final end = finishedAt ?? DateTime.now();
    final diff = end.difference(start).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  static const int quietAfterSeconds = 45;
}
