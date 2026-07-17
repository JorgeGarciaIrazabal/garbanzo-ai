import 'dart:math' as math;

/// Voice-activity events emitted by [TalkVad].
enum VadEvent {
  /// No state change on this sample.
  none,

  /// Audio rose above the start threshold — the user began speaking.
  speechStart,

  /// Silence persisted long enough after speech — the user finished.
  speechEnd,
}

/// Adaptive energy-based voice activity detection over amplitude samples.
///
/// Fed one dBFS reading at a time (from the recorder's amplitude stream), it
/// continuously tracks the **ambient noise floor** and detects speech relative
/// to it, rather than against fixed thresholds — so it works whether the room
/// tone sits at −55 dBFS (quiet) or −35 dBFS (noisy/high-gain mic). Speech
/// starts when the level rises [startMarginDb] above the floor; it ends once
/// the level falls back within [endMarginDb] of the floor for
/// [silenceDuration]. A [minSpeechDuration] floor debounces brief blips.
///
/// The floor only adapts while *not* speaking (so speech never inflates it),
/// adopting quieter levels quickly and drifting up slowly. Pure and
/// deterministic — the caller supplies `now`, so it is unit-testable without a
/// real clock or microphone.
class TalkVad {
  TalkVad({
    this.startMarginDb = 7,
    this.endMarginDb = 4,
    this.floorMinDb = -55,
    this.silenceDuration = const Duration(milliseconds: 900),
    this.minSpeechDuration = const Duration(milliseconds: 300),
    double initialNoiseFloorDb = -50,
  }) : _noiseFloor = initialNoiseFloorDb;

  /// dB above the noise floor at which speech is considered to have started.
  final double startMarginDb;

  /// dB above the noise floor below which a sample counts toward silence.
  final double endMarginDb;

  /// Lowest value the learned floor may take. Digitally-silent capture reads
  /// −160 dB (e.g. the `record` package on Android when its noise suppressor
  /// gates the mic between utterances); without a clamp, calibrating on such
  /// samples latches the floor so far down that real post-speech ambient never
  /// falls within [endMarginDb] of it and speech never ends.
  final double floorMinDb;

  /// How long the level must stay near the floor to end speech.
  final Duration silenceDuration;

  /// Minimum speech length before an end can be reported (debounces blips).
  final Duration minSpeechDuration;

  double _noiseFloor;
  bool _speaking = false;
  DateTime? _speechStartedAt;
  DateTime? _lastLoudAt;

  /// Number of leading samples used purely to measure the ambient floor before
  /// any speech can be detected (so a loud room doesn't self-trigger at start).
  static const _calibrationSamples = 3;
  int _calibrated = 0;

  bool get isSpeaking => _speaking;
  double get noiseFloorDb => _noiseFloor;

  /// Feed one amplitude reading. Returns the resulting [VadEvent].
  VadEvent update(double db, DateTime now) {
    if (!_speaking) {
      if (_calibrated < _calibrationSamples) {
        // Calibrate: snap the floor to the observed ambient (average of the
        // first few readings) without allowing a speech-start yet.
        final measured = _calibrated == 0 ? db : (_noiseFloor + db) / 2;
        _noiseFloor = math.max(measured, floorMinDb);
        _calibrated++;
        return VadEvent.none;
      }
      if (db > _noiseFloor + startMarginDb) {
        _speaking = true;
        _speechStartedAt = now;
        _lastLoudAt = now;
        return VadEvent.speechStart;
      }
      // Only track the floor on genuine (sub-threshold) ambient samples, never
      // on speech, so the floor can't creep up toward the user's voice.
      _adaptNoiseFloor(db);
      return VadEvent.none;
    }

    if (db > _noiseFloor + endMarginDb) {
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

  /// Track ambient level: move down quickly toward quieter readings, up slowly,
  /// so a brief loud blip doesn't inflate the floor and latch out real speech.
  void _adaptNoiseFloor(double db) {
    final alpha = db < _noiseFloor ? 0.3 : 0.05;
    _noiseFloor = math.max(
      _noiseFloor + (db - _noiseFloor) * alpha,
      floorMinDb,
    );
  }

  /// Enter the speaking state directly, as if speech had just started at
  /// [now]. Used when a voice barge-in carries an already-running capture into
  /// a fresh listen: the user is mid-utterance, so waiting for another
  /// speech-start would drop the words that triggered the interrupt.
  void forceSpeaking(DateTime now) {
    _speaking = true;
    _speechStartedAt = now;
    _lastLoudAt = now;
  }

  /// Clear speech state so the detector is ready for a fresh utterance. The
  /// learned noise floor is deliberately kept across utterances.
  void reset() {
    _speaking = false;
    _speechStartedAt = null;
    _lastLoudAt = null;
  }
}
