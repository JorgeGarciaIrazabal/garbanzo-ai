/// Live liveness state of an in-flight agent turn.
///
/// Small and immutable on purpose: it changes every few seconds as heartbeats
/// arrive, and it is published through its own [ValueNotifier] rather than the
/// chat provider's listener, so a heartbeat never rebuilds the transcript.
///
/// Everything here answers one of two questions: *is it still alive?* and
/// *what is it doing?* — the two things a user watching a long run needs.
class AgentLiveness {
  const AgentLiveness({
    required this.startedAt,
    this.secondsSinceSignal,
    this.elapsedSeconds,
    this.activity,
    this.steps = 0,
    this.completedCount = 0,
  });

  /// When this client first saw the run. Used for the elapsed fallback when
  /// the backend has not (yet) reported its own elapsed time.
  final DateTime startedAt;

  /// Seconds since the last signal of any kind — a heartbeat, a tool
  /// transition, or streamed text. Null before the first signal.
  final int? secondsSinceSignal;

  /// Elapsed seconds as reported by the backend heartbeat. Authoritative:
  /// unlike the local clock it is correct for a client that joined mid-run or
  /// whose device slept.
  final int? elapsedSeconds;

  /// What the backend last saw the agent doing (a file, a command).
  final String? activity;

  /// Steps the backend has counted, and how many tools it has finished.
  final int steps;
  final int completedCount;

  bool get isQuiet =>
      secondsSinceSignal != null && secondsSinceSignal! >= quietAfterSeconds;

  static const int quietAfterSeconds = 45;
}
