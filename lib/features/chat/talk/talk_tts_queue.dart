import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/services/tts_audio_source.dart';
import 'package:garbanzo_ai/features/chat/utils/text_cleaner.dart';
import 'package:garbanzo_ai/features/chat/utils/tts_text_chunks.dart';

/// Sequential text-to-speech playback for Talk Mode.
///
/// Splits text into sentence-sized chunks, synthesizes each via
/// [AudioService.speak], and plays them back-to-back. Enqueuing more text
/// while playing appends to the same queue, so a streamed reply can be spoken
/// sentence-by-sentence. [stop] cancels synthesis and playback immediately
/// (used for barge-in / interruption).
///
/// Mirrors the proven playback pattern in `speak_button.dart`: a fresh
/// [AudioPlayer] per chunk (reusing one is unreliable across web/Android/Linux).
class TalkTtsQueue {
  TalkTtsQueue({
    required this.voice,
    required this.speed,
    this.language,
    this.onComplete,
  });

  final String voice;
  final double speed;

  /// Target reply language (ISO code) — the backend swaps [voice] for that
  /// language's default voice when it doesn't speak it (idea 13.4). Null keeps
  /// [voice] as-is.
  final String? language;

  /// Called when the queue drains and nothing more is playing.
  final void Function()? onComplete;

  final List<String> _pending = [];
  bool _draining = false;
  bool _stopped = false;
  AudioPlayer? _player;
  PreparedTtsAudioSource? _audioSource;
  Completer<void>? _playbackDone;

  /// MP3 is the proven cross-platform playback path used by the regular
  /// message speak button. Android's MediaPlayer rejects some otherwise-valid
  /// WAV files with MEDIA_ERROR_SYSTEM before playback starts.
  @visibleForTesting
  static const audioFormat = 'mp3';

  bool get isSpeaking => _draining;

  /// Split cleaned text into ~sentence chunks (same heuristic as speak_button).
  @visibleForTesting
  static List<String> splitIntoChunks(String text) => splitTextForTts(text);

  /// Queue [text] for speech. Cleans markdown/emojis first; no-op if empty.
  void enqueue(String text) {
    if (_stopped) return;
    final cleaned = cleanTextForSpeech(text);
    if (cleaned.isEmpty) return;
    _pending.addAll(splitIntoChunks(cleaned));
    if (!_draining) unawaited(_drain());
  }

  Future<Uint8List> _synthesize(String chunk) => AudioService.instance.speak(
    chunk,
    voice: voice,
    speed: speed,
    format: audioFormat,
    language: language,
  );

  Future<void> _drain() async {
    _draining = true;
    // Keep one sentence synthesizing while the previous one plays, so there's
    // no audible gap waiting on the TTS round-trip between sentences.
    Future<Uint8List>? prefetched;
    try {
      while (!_stopped) {
        final current =
            prefetched ??
            (_pending.isNotEmpty ? _synthesize(_pending.removeAt(0)) : null);
        if (current == null) break;
        prefetched = _pending.isNotEmpty && !_stopped
            ? _synthesize(_pending.removeAt(0))
            : null;

        final audioBytes = await current;
        if (_stopped) break;
        await _playChunk(audioBytes);
      }
    } finally {
      _draining = false;
      if (!_stopped && _pending.isEmpty) onComplete?.call();
    }
  }

  Future<void> _playChunk(Uint8List audioBytes) async {
    // Fresh player per chunk — reusing one for sequential play() is unreliable
    // across platforms (matches speak_button).
    await _releasePlayback();
    final source = await prepareTtsAudioSource(audioBytes, format: audioFormat);
    if (_stopped) {
      await source.dispose();
      return;
    }
    final player = AudioPlayer();
    _player = player;
    _audioSource = source;
    final completer = Completer<void>();
    _playbackDone = completer;
    player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await player.play(source.source);
      await completer.future;
    } finally {
      if (identical(_playbackDone, completer)) _playbackDone = null;
      await _releasePlayback();
    }
  }

  /// Stop playback and clear the queue. The instance can be reused after
  /// [reset]; typically callers dispose and create a fresh queue per turn.
  Future<void> stop() async {
    _stopped = true;
    _pending.clear();
    await _player?.stop();
    final playbackDone = _playbackDone;
    if (playbackDone != null && !playbackDone.isCompleted) {
      playbackDone.complete();
    }
    await _releasePlayback();
    _draining = false;
  }

  Future<void> _releasePlayback() async {
    final player = _player;
    final source = _audioSource;
    _player = null;
    _audioSource = null;
    await player?.dispose();
    await source?.dispose();
  }

  /// Re-arm a stopped queue so it can accept new text again.
  void reset() => _stopped = false;
}
