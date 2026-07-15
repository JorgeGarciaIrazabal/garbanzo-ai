import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/utils/text_cleaner.dart';

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
  TalkTtsQueue({required this.voice, required this.speed, this.onComplete});

  final String voice;
  final double speed;

  /// Called when the queue drains and nothing more is playing.
  final void Function()? onComplete;

  final List<String> _pending = [];
  bool _draining = false;
  bool _stopped = false;
  AudioPlayer? _player;

  bool get isSpeaking => _draining;

  /// Split cleaned text into ~sentence chunks (same heuristic as speak_button).
  @visibleForTesting
  static List<String> splitIntoChunks(String text) {
    const targetSize = 500;
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final chunks = <String>[];
    final buf = StringBuffer();
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      if (buf.length + trimmed.length > targetSize && buf.isNotEmpty) {
        chunks.add(buf.toString().trim());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(trimmed);
    }
    if (buf.isNotEmpty) chunks.add(buf.toString().trim());
    return chunks;
  }

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
    // WAV avoids MP3 encoder priming that clips the first word on playback.
    format: 'wav',
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
    unawaited(_player?.dispose());
    _player = AudioPlayer();
    final completer = Completer<void>();
    _player!.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    await _player!.play(BytesSource(audioBytes));
    await completer.future;
  }

  /// Stop playback and clear the queue. The instance can be reused after
  /// [reset]; typically callers dispose and create a fresh queue per turn.
  Future<void> stop() async {
    _stopped = true;
    _pending.clear();
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _draining = false;
  }

  /// Re-arm a stopped queue so it can accept new text again.
  void reset() => _stopped = false;
}
