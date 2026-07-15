/// Voice-activity events emitted by [TalkVad].
enum VadEvent {
  /// No state change on this sample.
  none,

  /// Audio rose above the start threshold — the user began speaking.
  speechStart,

  /// Silence persisted long enough after speech — the user finished.
  speechEnd,
}

/// Energy-based voice activity detection over a stream of amplitude samples.
///
/// Fed one dBFS reading at a time (from the recorder's amplitude stream), it
/// tracks a tiny state machine: silence → speaking (level crosses
/// [startThresholdDb]) → silence for [silenceDuration] → [VadEvent.speechEnd].
/// A [minSpeechDuration] floor stops a brief cough/click from being treated as
/// a complete utterance.
///
/// Pure and deterministic — the caller supplies `now`, so it is unit-testable
/// without a real clock or microphone. Thresholds are dBFS (0 = loudest,
/// more negative = quieter) and are the main thing to tune on-device.
class TalkVad {
  TalkVad({
    this.startThresholdDb = -35,
    this.silenceThresholdDb = -42,
    this.silenceDuration = const Duration(milliseconds: 1000),
    this.minSpeechDuration = const Duration(milliseconds: 300),
  });

  /// Level (dBFS) above which we consider the user to have started speaking.
  final double startThresholdDb;

  /// Level (dBFS) below which a sample counts toward trailing silence.
  final double silenceThresholdDb;

  /// How long the level must stay below [silenceThresholdDb] to end speech.
  final Duration silenceDuration;

  /// Minimum speech length before an end can be reported (debounces blips).
  final Duration minSpeechDuration;

  bool _speaking = false;
  DateTime? _speechStartedAt;
  DateTime? _lastLoudAt;

  bool get isSpeaking => _speaking;

  /// Feed one amplitude reading. Returns the resulting [VadEvent].
  VadEvent update(double db, DateTime now) {
    if (!_speaking) {
      if (db > startThresholdDb) {
        _speaking = true;
        _speechStartedAt = now;
        _lastLoudAt = now;
        return VadEvent.speechStart;
      }
      return VadEvent.none;
    }

    if (db > silenceThresholdDb) {
      _lastLoudAt = now;
      return VadEvent.none;
    }

    final sinceLoud = now.difference(_lastLoudAt!);
    final sinceStart = now.difference(_speechStartedAt!);
    if (sinceLoud >= silenceDuration && sinceStart >= minSpeechDuration) {
      reset();
      return VadEvent.speechEnd;
    }
    return VadEvent.none;
  }

  /// Clear state so the detector is ready for a fresh utterance.
  void reset() {
    _speaking = false;
    _speechStartedAt = null;
    _lastLoudAt = null;
  }
}
