import 'dart:collection';
import 'dart:math' as math;

/// Detects the user talking over the AI (voice barge-in) from the amplitude
/// stream while a reply is playing.
///
/// Three defenses keep residual AEC echo and room noise from self-triggering:
///
/// - a **wide relative margin**: samples only count as "the user" when they
///   rise [marginDb] above the reference floor (the ambient floor the VAD
///   learned while listening, handed in via [arm]);
/// - an **absolute gate**: samples below [absoluteGateDb] never count, even
///   when a very quiet pre-turn room put the learned floor absurdly low;
/// - **speaking-period floor adaptation**: sub-threshold samples during the
///   reply (i.e. the AI's residual echo) pull the floor upward, so sustained
///   echo raises the bar instead of sneaking under a floor that was learned
///   in silence and never re-checked.
///
/// The trigger itself is a sliding window — [requiredLoud] loud samples out
/// of the last [windowSize] — so natural intra-word dips don't reset the
/// count (the old strict consecutive-run did), but a lone slam of a door
/// can't interrupt either. Pure and deterministic: no clocks, no I/O.
class TalkBargeIn {
  TalkBargeIn({
    this.marginDb = 18,
    this.absoluteGateDb = -45,
    this.windowSize = 8,
    this.requiredLoud = 6,
  });

  /// dB above the reference floor a sample must reach to count as the user.
  final double marginDb;

  /// Absolute dBFS below which samples never count, whatever the floor is.
  final double absoluteGateDb;

  /// How many recent samples the sliding window holds (~100 ms each).
  final int windowSize;

  /// Loud samples required within the window to fire an interrupt.
  final int requiredLoud;

  double _floor = -50;
  final Queue<bool> _recent = Queue();

  /// Reference floor currently in use (learned floor + echo adaptation).
  double get floorDb => _floor;

  /// Level a sample must exceed to count toward an interrupt.
  double get thresholdDb => math.max(_floor + marginDb, absoluteGateDb);

  /// Start monitoring a fresh reply, using the ambient floor the VAD learned
  /// during the preceding listening phase as the starting reference.
  void arm(double listeningFloorDb) {
    _floor = listeningFloorDb;
    _recent.clear();
  }

  /// Feed one amplitude reading. Returns true when the user has been loud
  /// long enough that the AI should be interrupted; the window resets so a
  /// carried-over capture doesn't immediately re-fire.
  bool update(double db) {
    final loud = db > thresholdDb;
    if (!loud) _adaptFloor(db);
    _recent.addLast(loud);
    if (_recent.length > windowSize) _recent.removeFirst();
    if (_recent.where((l) => l).length >= requiredLoud) {
      _recent.clear();
      return true;
    }
    return false;
  }

  /// Track the reply-period ambient (residual echo included): rise moderately
  /// toward louder sub-threshold sound, fall quickly when it goes quiet.
  /// Above-threshold samples never adapt — that's the user, not the room.
  void _adaptFloor(double db) {
    final alpha = db < _floor ? 0.3 : 0.1;
    _floor += (db - _floor) * alpha;
  }
}
