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
  bool _needsPlaybackPreroll = true;
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
        final playbackBytes = _needsPlaybackPreroll
            ? prependWavSilence(audioBytes, playbackPreroll)
            : audioBytes;
        _needsPlaybackPreroll = false;
        await _playChunk(playbackBytes);
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

  /// A short silent lead-in protects the first spoken samples while a cold
  /// audio output path (especially Android/Bluetooth) wakes up. It is applied
  /// once per assistant turn, not before every sentence.
  @visibleForTesting
  static const playbackPreroll = Duration(milliseconds: 500);

  /// Insert PCM silence before a WAV file's `data` payload.
  ///
  /// Unknown or unsupported WAV layouts are returned unchanged instead of
  /// risking corrupt audio. Kokoro produces mono PCM16, but the byte-rate and
  /// block alignment are read from the header so this remains format-safe.
  @visibleForTesting
  static Uint8List prependWavSilence(Uint8List wav, Duration duration) {
    if (duration <= Duration.zero ||
        wav.lengthInBytes < 44 ||
        _ascii(wav, 0, 4) != 'RIFF' ||
        _ascii(wav, 8, 12) != 'WAVE') {
      return wav;
    }

    final header = ByteData.sublistView(wav);
    int? byteRate;
    int? blockAlign;
    int? dataSizeOffset;
    int? dataOffset;
    var offset = 12;
    while (offset + 8 <= wav.lengthInBytes) {
      final chunkId = _ascii(wav, offset, offset + 4);
      final chunkSize = header.getUint32(offset + 4, Endian.little);
      final chunkData = offset + 8;
      if (chunkData + chunkSize > wav.lengthInBytes) return wav;

      if (chunkId == 'fmt ' && chunkSize >= 16) {
        final audioFormat = header.getUint16(chunkData, Endian.little);
        if (audioFormat != 1) return wav;
        byteRate = header.getUint32(chunkData + 8, Endian.little);
        blockAlign = header.getUint16(chunkData + 12, Endian.little);
      } else if (chunkId == 'data') {
        dataSizeOffset = offset + 4;
        dataOffset = chunkData;
        break;
      }
      offset = chunkData + chunkSize + chunkSize.remainder(2);
    }

    if (byteRate == null ||
        byteRate <= 0 ||
        blockAlign == null ||
        blockAlign <= 0 ||
        dataSizeOffset == null ||
        dataOffset == null) {
      return wav;
    }

    final requestedBytes = byteRate * duration.inMicroseconds ~/ 1000000;
    final silenceBytes = requestedBytes - requestedBytes.remainder(blockAlign);
    if (silenceBytes == 0) return wav;

    final output = Uint8List(wav.lengthInBytes + silenceBytes);
    output.setRange(0, dataOffset, wav);
    output.setRange(
      dataOffset + silenceBytes,
      output.lengthInBytes,
      wav,
      dataOffset,
    );
    final outputHeader = ByteData.sublistView(output);
    final oldDataSize = header.getUint32(dataSizeOffset, Endian.little);
    outputHeader
      ..setUint32(4, output.lengthInBytes - 8, Endian.little)
      ..setUint32(dataSizeOffset, oldDataSize + silenceBytes, Endian.little);
    return output;
  }

  static String _ascii(Uint8List bytes, int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));

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
  void reset() {
    _stopped = false;
    _needsPlaybackPreroll = true;
  }
}
