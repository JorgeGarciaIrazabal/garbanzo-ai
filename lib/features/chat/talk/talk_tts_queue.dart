import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/services/tts_audio_source.dart';
import 'package:garbanzo_ai/features/chat/utils/text_cleaner.dart';
import 'package:garbanzo_ai/features/chat/utils/tts_text_chunks.dart';

class _PreparedTtsChunk {
  _PreparedTtsChunk._({
    this.player,
    this.source,
    this.completion,
    this.completionSubscription,
    this.testPlayer,
  });

  final AudioPlayer? player;
  final PreparedTtsAudioSource? source;
  final Completer<void>? completion;
  final StreamSubscription<void>? completionSubscription;
  final Future<void> Function()? testPlayer;
  bool _disposed = false;

  static Future<_PreparedTtsChunk> prepare(Uint8List bytes) async {
    final source = await prepareTtsAudioSource(
      bytes,
      format: TalkTtsQueue.audioFormat,
    );
    final player = AudioPlayer();
    final completion = Completer<void>();
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completion.isCompleted) completion.complete();
    });
    try {
      // Decode and prepare while the previous chunk is still playing. At the
      // boundary resume() only has to start an already-ready source.
      await player.setSource(source.source);
      return _PreparedTtsChunk._(
        player: player,
        source: source,
        completion: completion,
        completionSubscription: subscription,
      );
    } catch (_) {
      await subscription.cancel();
      await player.dispose();
      await source.dispose();
      rethrow;
    }
  }

  factory _PreparedTtsChunk.forTest(
    Uint8List bytes,
    Future<void> Function(Uint8List audioBytes) play,
  ) => _PreparedTtsChunk._(testPlayer: () => play(bytes));

  Future<void> play() async {
    final playForTest = testPlayer;
    if (playForTest != null) {
      await playForTest();
      return;
    }
    await player!.resume();
    await completion!.future;
  }

  Future<void> stop() async {
    await player?.stop();
    final done = completion;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await completionSubscription?.cancel();
    await player?.dispose();
    await source?.dispose();
  }
}

/// Sequential text-to-speech playback for Talk Mode.
///
/// Splits text into bounded chunks, synthesizes each via
/// [AudioService.speak], and plays them back-to-back. Enqueuing more text
/// while playing appends to the same queue, so a streamed reply can be spoken
/// sentence-by-sentence. [stop] cancels synthesis and playback immediately
/// (used for barge-in / interruption).
///
/// A fresh [AudioPlayer] is prepared for the next chunk during current
/// playback (reusing one is unreliable across web/Android/Linux).
class TalkTtsQueue {
  TalkTtsQueue({
    required this.voice,
    required this.speed,
    this.language,
    this.onComplete,
    Future<Uint8List> Function(String chunk)? synthesizer,
    Future<void> Function(Uint8List audioBytes)? chunkPlayer,
  }) : _synthesizer = synthesizer,
       _chunkPlayer = chunkPlayer;

  final String voice;
  final double speed;

  /// Target reply language (ISO code) — the backend swaps [voice] for that
  /// language's default voice when it doesn't speak it (idea 13.4). Null keeps
  /// [voice] as-is.
  final String? language;

  /// Called when the queue drains and nothing more is playing.
  final void Function()? onComplete;

  final Future<Uint8List> Function(String chunk)? _synthesizer;
  final Future<void> Function(Uint8List audioBytes)? _chunkPlayer;

  final List<String> _pending = [];
  Future<_PreparedTtsChunk?>? _prefetched;
  bool _draining = false;
  bool _stopped = false;
  _PreparedTtsChunk? _activeChunk;

  /// MP3 is the proven cross-platform playback path used by the regular
  /// message speak button. Android's MediaPlayer rejects some otherwise-valid
  /// WAV files with MEDIA_ERROR_SYSTEM before playback starts.
  @visibleForTesting
  static const audioFormat = 'mp3';

  bool get isSpeaking => _draining;

  /// Split cleaned text into API-bounded chunks.
  @visibleForTesting
  static List<String> splitIntoChunks(String text) => splitTextForTts(text);

  /// Queue [text] for speech. Cleans markdown/emojis first; no-op if empty.
  void enqueue(String text) {
    if (_stopped) return;
    final cleaned = cleanTextForSpeech(text);
    if (cleaned.isEmpty) return;
    _pending.addAll(splitIntoChunks(cleaned));
    _startPrefetch();
    if (!_draining) {
      _draining = true;
      unawaited(_drain());
    }
  }

  Future<Uint8List> _synthesize(String chunk) {
    final synthesizer = _synthesizer;
    if (synthesizer != null) return synthesizer(chunk);
    return AudioService.instance.speak(
      chunk,
      voice: voice,
      speed: speed,
      format: audioFormat,
      language: language,
    );
  }

  Future<_PreparedTtsChunk?> _prepareChunk(String chunk) async {
    final audioBytes = await _synthesize(chunk);
    if (_stopped) return null;
    final chunkPlayer = _chunkPlayer;
    final prepared = chunkPlayer == null
        ? await _PreparedTtsChunk.prepare(audioBytes)
        : _PreparedTtsChunk.forTest(audioBytes, chunkPlayer);
    if (!_stopped) return prepared;
    await prepared.dispose();
    return null;
  }

  void _startPrefetch() {
    if (_stopped || _prefetched != null || _pending.isEmpty) return;
    _prefetched = _prepareChunk(_pending.removeAt(0));
  }

  Future<void> _drain() async {
    try {
      while (!_stopped) {
        _startPrefetch();
        final current = _prefetched;
        if (current == null) break;
        _prefetched = null;

        final prepared = await current;
        if (_stopped || prepared == null) break;
        await _playChunk(prepared);
      }
    } finally {
      _draining = false;
      if (!_stopped && _pending.isEmpty) onComplete?.call();
    }
  }

  Future<void> _playChunk(_PreparedTtsChunk prepared) async {
    _activeChunk = prepared;
    try {
      await prepared.play();
    } finally {
      if (identical(_activeChunk, prepared)) _activeChunk = null;
      await prepared.dispose();
    }
  }

  /// Stop playback and clear the queue. The instance can be reused after
  /// [reset]; typically callers dispose and create a fresh queue per turn.
  Future<void> stop() async {
    _stopped = true;
    _pending.clear();
    final prefetched = _prefetched;
    _prefetched = null;
    if (prefetched != null) {
      unawaited(_disposeWhenReady(prefetched));
    }
    final active = _activeChunk;
    _activeChunk = null;
    await active?.stop();
    await active?.dispose();
    _draining = false;
  }

  Future<void> _disposeWhenReady(Future<_PreparedTtsChunk?> future) async {
    try {
      await (await future)?.dispose();
    } catch (_) {
      // An interrupted request has no user-visible result to surface.
    }
  }

  /// Re-arm a stopped queue so it can accept new text again.
  void reset() => _stopped = false;
}
