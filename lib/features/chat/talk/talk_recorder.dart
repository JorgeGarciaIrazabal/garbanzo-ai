import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/voice_recording_helper.dart';

/// Recorder dedicated to Talk Mode: captures WAV (16 kHz mono) while streaming
/// a live amplitude reading for voice-activity detection.
///
/// Unlike the chat-input [VoiceRecordingHelper] (which shells out to `arecord`
/// on Linux and has no amplitude stream), this always uses the `record`
/// package so `onAmplitudeChanged` is available for VAD on every platform.
/// On Linux that routes through `parecord` (PulseAudio) — amplitude support
/// there is less battle-tested than mobile/web, so callers keep tap-to-send as
/// a guaranteed fallback if no samples arrive.
class TalkRecorder {
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;

  /// Start capturing. [onDb] receives amplitude readings in dBFS (~every
  /// 100 ms) to drive VAD. Throws [VoiceRecordingException] on failure.
  Future<void> start({required void Function(double db) onDb}) async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      throw const VoiceRecordingException('Microphone permission denied');
    }

    _path =
        '${Directory.systemTemp.path}/garbanzo_talk_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _path!,
      );
    } catch (e) {
      await recorder.dispose();
      _path = null;
      throw VoiceRecordingException('Failed to start recording: $e');
    }

    _recorder = recorder;
    _ampSub = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen(
          (amp) => onDb(amp.current),
          onError: (Object e) => debugPrint('TalkRecorder amplitude error: $e'),
        );
  }

  /// Stop capturing and transcribe. Returns `null` if nothing was recorded.
  Future<VoiceRecordingResult?> stopAndTranscribe() async {
    await _ampSub?.cancel();
    _ampSub = null;
    final path = await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;
    _path = null;

    if (path == null) return null;
    final file = File(path);
    final audioBytes = await file.exists()
        ? await file.readAsBytes()
        : Uint8List(0);
    if (audioBytes.isEmpty) return null;

    try {
      final transcript = await AudioService.instance.transcribeAudio(
        audioBytes,
        path.split('/').last,
      );
      return VoiceRecordingResult(transcript: transcript);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Cancel any active capture and release resources.
  void dispose() {
    unawaited(_ampSub?.cancel());
    _ampSub = null;
    unawaited(_recorder?.dispose());
    _recorder = null;
    _path = null;
  }
}
