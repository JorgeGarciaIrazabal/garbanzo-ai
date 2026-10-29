import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/features/chat/models/agent_liveness.dart';

/// Tracks live heartbeat/tool-progress signals during an active assistant turn.
///
/// Kept separate from the transcript list so frequent heartbeats only rebuild
/// the progress card listening to [notifier], never the whole chat view.
class AgentLivenessController {
  final ValueNotifier<AgentLiveness?> notifier = ValueNotifier<AgentLiveness?>(
    null,
  );

  DateTime? _signalAt;
  DateTime? _startedAt;
  Map<String, dynamic>? _heartbeat;

  /// Record that the agent reported forward progress and refresh the clock.
  void noteSignal() {
    _startedAt ??= DateTime.now();
    _signalAt = DateTime.now();
    _publish();
  }

  void applyHeartbeat(Map<String, dynamic>? heartbeat) {
    if (heartbeat == null) return;
    _heartbeat = heartbeat;
    noteSignal();
  }

  void reset() {
    _startedAt = null;
    _signalAt = null;
    _heartbeat = null;
    notifier.value = null;
  }

  void _publish() {
    final started = _startedAt;
    if (started == null) {
      notifier.value = null;
      return;
    }
    final beat = _heartbeat;
    notifier.value = AgentLiveness(
      startedAt: started,
      secondsSinceSignal: _signalAt == null
          ? null
          : DateTime.now().difference(_signalAt!).inSeconds,
      elapsedSeconds: _intOrNull(beat?['elapsed_s']),
      activity: beat?['activity']?.toString(),
      steps: _intOrNull(beat?['steps']) ?? 0,
      completedCount: _intOrNull(beat?['tools_completed']) ?? 0,
    );
  }

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void dispose() {
    notifier.dispose();
  }
}
