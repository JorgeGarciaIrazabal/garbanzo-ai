import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/voice_recording_helper.dart';

/// Recorder dedicated to Talk Mode: captures WAV (16 kHz mono) while streaming
/// a live amplitude reading (dBFS) for voice-activity detection.
///
/// Two backends:
/// - **Linux desktop** streams raw PCM from `arecord` (ALSA) to stdout, so we
///   get amplitude *and* audio without needing PulseAudio's `parecord` (which
///   the `record` package requires and isn't always installed). RMS over each
///   PCM chunk gives the dBFS level; the bytes are wrapped into a WAV for STT.
///   It records from the ALSA `default` device — which on PipeWire/PulseAudio
///   routes to the user's configured mic and, crucially, *shares* the device
///   (opening a specific `plughw:card` fails with "Device or resource busy"
///   when the sound server already holds it, and can grab a dead/floating
///   input on multi-card laptops).
/// - **Everywhere else** uses the `record` package, whose `onAmplitudeChanged`
///   provides the level directly.
///
/// Callers keep tap-to-send as a fallback if no amplitude samples arrive.
class TalkRecorder {
  // record-package backend (mobile / web / macOS / Windows).
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;

  // arecord backend (Linux).
  Process? _arecord;
  StreamSubscription<List<int>>? _pcmSub;
  final BytesBuilder _pcm = BytesBuilder(copy: false);

  static const _sampleRate = 16000;
  static const _channels = 1;

  bool get _useArecord => !kIsWeb && Platform.isLinux;

  /// Start capturing. [onDb] receives amplitude readings in dBFS (~every
  /// 100 ms) to drive VAD. Throws [VoiceRecordingException] on failure.
  Future<void> start({required void Function(double db) onDb}) async {
    // Drop any prior session first so back-to-back starts (e.g. barge-in →
    // fresh listen) never leak a recorder.
    dispose();
    if (_useArecord) {
      await _startArecord(onDb);
    } else {
      await _startRecordPackage(onDb);
    }
  }

  /// Stop capturing and transcribe. Returns `null` if nothing was recorded.
  Future<VoiceRecordingResult?> stopAndTranscribe() async {
    return _useArecord ? _stopArecord() : _stopRecordPackage();
  }

  /// Cancel any active capture and release resources. Deletes the in-progress
  /// recording (e.g. a discarded barge-in session).
  void dispose() {
    unawaited(_ampSub?.cancel());
    _ampSub = null;
    final recorder = _recorder;
    final path = _path;
    _recorder = null;
    _path = null;
    unawaited(_teardownRecordPackage(recorder, path));

    unawaited(_pcmSub?.cancel());
    _pcmSub = null;
    _arecord?.kill(ProcessSignal.sigint);
    _arecord = null;
    _pcm.clear();
  }

  // -- arecord backend (Linux) ----------------------------------------------

  Future<void> _startArecord(void Function(double db) onDb) async {
    final Process proc;
    try {
      proc = await Process.start('arecord', [
        '-D',
        'default',
        '-f',
        'S16_LE',
        '-r',
        '$_sampleRate',
        '-c',
        '$_channels',
        '-t',
        'raw',
      ]);
    } catch (e) {
      throw VoiceRecordingException('Failed to start recording: $e');
    }
    _arecord = proc;
    _pcm.clear();
    _levelRemainder = Uint8List(0);
    _pcmSub = proc.stdout.listen((chunk) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      _pcm.add(bytes);
      _emitLevels(bytes, onDb);
    }, onError: (Object e) => debugPrint('TalkRecorder arecord error: $e'));
  }

  Uint8List _levelRemainder = Uint8List(0);

  /// Emit one dBFS reading per fixed 100 ms window regardless of how `arecord`
  /// chunks its stdout, so VAD timing (and the visualizer) stay responsive.
  /// Bytes that don't fill a window carry over to the next chunk.
  void _emitLevels(Uint8List bytes, void Function(double db) onDb) {
    const frame = _sampleRate ~/ 10 * 2; // 100 ms of mono S16 = 3200 bytes
    final buf = _levelRemainder.isEmpty
        ? bytes
        : (BytesBuilder()
                ..add(_levelRemainder)
                ..add(bytes))
              .takeBytes();
    var off = 0;
    while (off + frame <= buf.length) {
      onDb(rmsDbfs(Uint8List.sublistView(buf, off, off + frame)));
      off += frame;
    }
    _levelRemainder = Uint8List.sublistView(buf, off);
  }

  Future<VoiceRecordingResult?> _stopArecord() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    _arecord?.kill(ProcessSignal.sigint);
    await _arecord?.exitCode;
    _arecord = null;

    final pcm = _pcm.takeBytes();
    if (pcm.isEmpty) return null;
    final wav = wrapPcmInWav(pcm, sampleRate: _sampleRate, channels: _channels);
    final transcript = await AudioService.instance.transcribeAudio(
      wav,
      'talk.wav',
    );
    return VoiceRecordingResult(transcript: transcript);
  }

  // -- record-package backend (mobile / web / macOS / Windows) ---------------

  Future<void> _startRecordPackage(void Function(double db) onDb) async {
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
          sampleRate: _sampleRate,
          numChannels: _channels,
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

  Future<VoiceRecordingResult?> _stopRecordPackage() async {
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

  static Future<void> _teardownRecordPackage(
    AudioRecorder? recorder,
    String? path,
  ) async {
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (_) {}
      await recorder.dispose();
    }
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  // -- PCM helpers (pure, unit-tested) --------------------------------------

  /// RMS level of a little-endian S16 PCM [chunk], in dBFS (0 = full scale,
  /// more negative = quieter). Returns a floor for silence/empty input.
  @visibleForTesting
  static double rmsDbfs(Uint8List chunk) {
    final sampleCount = chunk.lengthInBytes ~/ 2;
    if (sampleCount == 0) return -160;
    final data = ByteData.sublistView(chunk);
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    if (rms <= 0) return -160;
    return 20 * math.log(rms) / math.ln10;
  }

  /// Wrap raw little-endian S16 [pcm] in a 44-byte PCM WAV container.
  @visibleForTesting
  static Uint8List wrapPcmInWav(
    Uint8List pcm, {
    required int sampleRate,
    required int channels,
  }) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLen = pcm.lengthInBytes;

    final out = BytesBuilder();
    void str(String s) => out.add(s.codeUnits);
    void u32(int v) => out.add(
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
    );
    void u16(int v) => out.add(
      (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
    );

    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16); // PCM fmt chunk size
    u16(1); // audio format = PCM
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    str('data');
    u32(dataLen);
    out.add(pcm);
    return out.takeBytes();
  }
}
