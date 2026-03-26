import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../services/audio_service.dart';

/// Result of a completed voice recording + transcription.
class VoiceRecordingResult {
  const VoiceRecordingResult({required this.transcript});
  final String transcript;
}

/// Manages voice recording and transcription, keeping platform-specific
/// logic (ALSA, PulseAudio, mobile recorder) out of the input widget.
class VoiceRecordingHelper {
  AudioRecorder? _recorder;
  Process? _arecordProcess;
  String? _arecordPath;

  bool get isUsingArecord => _arecordProcess != null;

  /// Start recording audio. Returns `true` if recording started successfully.
  /// Throws a [VoiceRecordingException] on failure.
  Future<bool> startRecording() async {
    final tempPath =
        '${Directory.systemTemp.path}/garbanzo_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    if (Platform.isAndroid || Platform.isIOS) {
      return _startMobileRecording(tempPath);
    } else {
      return _startDesktopRecording(tempPath);
    }
  }

  /// Stop recording and transcribe the audio.
  /// Returns the transcription result, or `null` if no audio was captured.
  /// Throws a [VoiceRecordingException] on failure.
  Future<VoiceRecordingResult?> stopAndTranscribe() async {
    String? path;

    if (_arecordProcess != null) {
      _arecordProcess!.kill(ProcessSignal.sigint);
      await _arecordProcess!.exitCode;
      path = _arecordPath;
      _arecordProcess = null;
      _arecordPath = null;
    } else {
      path = await _recorder?.stop();
      _recorder?.dispose();
      _recorder = null;
    }

    if (path == null) {
      debugPrint('STT: recording path is null');
      return null;
    }

    final file = File(path);
    final exists = await file.exists();
    final audioBytes = exists ? await file.readAsBytes() : Uint8List(0);
    final filename = path.split('/').last;
    debugPrint('STT: path=$path exists=$exists size=${audioBytes.length} bytes');

    if (audioBytes.isEmpty) {
      debugPrint('STT: audio file is empty, skipping transcription');
      throw const VoiceRecordingException('Recording failed — audio file is empty');
    }

    try {
      final transcript =
          await AudioService.instance.transcribeAudio(audioBytes, filename);
      debugPrint('STT: transcript="$transcript" (${transcript.length} chars)');
      return VoiceRecordingResult(transcript: transcript);
    } finally {
      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Cancel any active recording and release resources.
  void dispose() {
    _recorder?.dispose();
    _recorder = null;
    _arecordProcess?.kill();
    _arecordProcess = null;
    _arecordPath = null;
  }

  // -- Private helpers -------------------------------------------------------

  Future<bool> _startMobileRecording(String tempPath) async {
    _recorder = AudioRecorder();
    final hasPermission = await _recorder!.hasPermission();
    if (!hasPermission) {
      _recorder?.dispose();
      _recorder = null;
      throw const VoiceRecordingException('Microphone permission denied');
    }
    try {
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: tempPath,
      );
      return true;
    } catch (e) {
      _recorder?.dispose();
      _recorder = null;
      throw VoiceRecordingException('Failed to start recording: $e');
    }
  }

  Future<bool> _startDesktopRecording(String tempPath) async {
    // Try arecord with direct ALSA hardware access first
    if (await _hasBinary('arecord')) {
      try {
        final card = await _findAlsaCaptureCard();
        final device = card != null ? 'plughw:$card,0' : 'default';
        _arecordPath = tempPath;
        _arecordProcess = await Process.start('arecord', [
          '-D', device,
          '-f', 'S16_LE',
          '-r', '44100',
          '-c', '1',
          tempPath,
        ]);
        return true;
      } catch (e) {
        _arecordProcess = null;
        _arecordPath = null;
      }
    }

    // Fallback: try the record package (uses parecord)
    if (await _hasBinary('parecord')) {
      try {
        _recorder = AudioRecorder();
        final hasPermission = await _recorder!.hasPermission();
        if (!hasPermission) {
          _recorder?.dispose();
          _recorder = null;
          throw const VoiceRecordingException('Microphone permission denied');
        }
        await _recorder!.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: tempPath,
        );
        return true;
      } catch (e) {
        _recorder?.dispose();
        _recorder = null;
        if (e is VoiceRecordingException) rethrow;
      }
    }

    throw const VoiceRecordingException(
      'Microphone not available. Install alsa-utils or pulseaudio-utils.',
    );
  }

  Future<bool> _hasBinary(String name) async {
    try {
      final result = await Process.run('which', [name]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Find the best ALSA capture card by parsing `arecord -l`.
  Future<String?> _findAlsaCaptureCard() async {
    try {
      final result = await Process.run('arecord', ['-l']);
      if (result.exitCode != 0) return null;

      final output = result.stdout as String;
      final lineRe = RegExp(r'card\s+(\d+):\s+\S+\s+\[(.+?)\]');

      String? bestCard;
      String? firstCard;

      for (final match in lineRe.allMatches(output)) {
        final cardNum = match.group(1)!;
        final name = match.group(2)!.toLowerCase();

        firstCard ??= cardNum;

        if (name.contains('dock') || name.contains('hdmi')) continue;

        bestCard ??= cardNum;
      }

      return bestCard ?? firstCard;
    } catch (_) {
      return null;
    }
  }
}

class VoiceRecordingException implements Exception {
  const VoiceRecordingException(this.message);
  final String message;

  @override
  String toString() => message;
}
