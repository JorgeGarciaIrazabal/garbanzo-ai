import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';

/// Result of a completed voice recording + transcription.
class VoiceRecordingResult {
  const VoiceRecordingResult({required this.transcript, this.language});
  final String transcript;

  /// ISO 639-1 language STT detected in the clip, null if unknown. Talk Mode
  /// uses it to reply in the language the user spoke (idea 13.4).
  final String? language;
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
      unawaited(_recorder?.dispose());
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
    debugPrint(
      'STT: path=$path exists=$exists size=${audioBytes.length} bytes',
    );

    if (audioBytes.isEmpty) {
      debugPrint('STT: audio file is empty, skipping transcription');
      throw const VoiceRecordingException(
        'Recording failed — audio file is empty',
      );
    }

    try {
      final result = await AudioService.instance.transcribeAudio(
        audioBytes,
        filename,
      );
      debugPrint(
        'STT: transcript="${result.text}" (${result.text.length} chars, '
        'lang=${result.language})',
      );
      return VoiceRecordingResult(
        transcript: result.text,
        language: result.language,
      );
    } finally {
      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Cancel any active recording and release resources.
  void dispose() {
    unawaited(_recorder?.dispose());
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
      unawaited(_recorder?.dispose());
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
      unawaited(_recorder?.dispose());
      _recorder = null;
      throw VoiceRecordingException('Failed to start recording: $e');
    }
  }

  Future<bool> _startDesktopRecording(String tempPath) async {
    // Try arecord first. Use the ALSA `default` device, not a specific
    // `plughw:card`: on PipeWire, opening a hardware card directly fails with
    // "Device or resource busy", and picking a card by index can grab a dead
    // or floating input (→ silent/hallucinated transcription). `default`
    // routes to the user's configured mic and shares the device.
    if (await _hasBinary('arecord')) {
      try {
        _arecordPath = tempPath;
        _arecordProcess = await Process.start('arecord', [
          '-D',
          'default',
          '-f',
          'S16_LE',
          '-r',
          '16000',
          '-c',
          '1',
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
          unawaited(_recorder?.dispose());
          _recorder = null;
          throw const VoiceRecordingException('Microphone permission denied');
        }
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
        unawaited(_recorder?.dispose());
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
}

class VoiceRecordingException implements Exception {
  const VoiceRecordingException(this.message);
  final String message;

  @override
  String toString() => message;
}
