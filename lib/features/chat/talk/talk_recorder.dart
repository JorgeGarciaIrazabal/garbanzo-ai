import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/talk/pipewire_echo_cancel.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/voice_recording_helper.dart';

/// Recorder dedicated to Talk Mode: captures WAV (16 kHz mono) while streaming
/// a live amplitude reading (dBFS) for voice-activity detection.
///
/// Two backends:
/// - **Linux desktop** streams raw PCM to stdout from a subprocess. It prefers
///   `pw-record` reading a PipeWire **echo-cancelled** source (so the AI's own
///   playback is removed and voice barge-in works over speakers — see
///   [PipewireEchoCancel]); if AEC can't be set up it falls back to
///   `arecord -D default`. Either way RMS over each PCM chunk gives the dBFS
///   level and the bytes are wrapped into a WAV for STT. Using the `default`
///   device (not a specific `plughw:card`) shares the mic with the sound
///   server and avoids grabbing a dead/floating input on multi-card laptops.
/// - **Everywhere else** uses the `record` package (with `echoCancel` enabled
///   so mobile hardware AEC kicks in), whose `onAmplitudeChanged` gives level.
///
/// Callers keep tap-to-send as a fallback if no amplitude samples arrive.
class TalkRecorder {
  // record-package backend (mobile / web / macOS / Windows).
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;

  // subprocess backend (Linux: pw-record from AEC source, or arecord).
  Process? _capture;
  StreamSubscription<List<int>>? _pcmSub;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  final PipewireEchoCancel _aec = PipewireEchoCancel();

  static const _sampleRate = 16000;
  static const _channels = 1;

  bool get _useSubprocess => !kIsWeb && Platform.isLinux;

  bool _echoCancelActive = false;

  /// Bumped on every [dispose] so an in-flight [start] (which has async gaps —
  /// AEC load, permission, process spawn) can detect it was superseded and not
  /// leak an orphaned capture process.
  int _startGen = 0;
  bool _isShutdown = false;

  /// Whether the current capture path removes the AI's TTS echo — a
  /// prerequisite for enabling voice barge-in without self-interruption.
  /// True on Linux when the PipeWire echo-cancel source is in use, and on
  /// mobile where the OS provides hardware AEC.
  bool get echoCancellationActive => _echoCancelActive;

  /// Start capturing. [onDb] receives amplitude readings in dBFS (~every
  /// 100 ms) to drive VAD. Throws [VoiceRecordingException] on failure.
  Future<void> start({required void Function(double db) onDb}) async {
    if (_isShutdown) return;
    // Drop any prior capture first so back-to-back starts (e.g. barge-in →
    // fresh listen) never leak a process. Keeps the AEC module loaded.
    dispose();
    if (_useSubprocess) {
      await _startSubprocess(onDb);
    } else {
      await _startRecordPackage(onDb);
    }
  }

  /// Stop capturing and transcribe. Returns `null` if nothing was recorded.
  Future<VoiceRecordingResult?> stopAndTranscribe() async {
    return _useSubprocess ? _stopSubprocess() : _stopRecordPackage();
  }

  /// Whether the running capture can be carried across an interrupt→listen
  /// transition without a restart. Only the subprocess backend buffers PCM in
  /// memory where it can be trimmed; the record-package backend writes to a
  /// file we can't rewrite mid-capture.
  bool get supportsCarryOver => _capture != null;

  /// Drop all but the trailing [keep] of buffered PCM, leaving capture
  /// running. Used on voice barge-in: the buffer holds the whole
  /// (echo-cancelled) reply period, but only the user's interrupting words at
  /// the end are worth transcribing.
  void trimBufferToLast(Duration keep) {
    if (_capture == null) return;
    final maxBytes = _sampleRate * 2 * keep.inMilliseconds ~/ 1000;
    _pcm.add(tailPcm(_pcm.takeBytes(), maxBytes));
  }

  /// The trailing [maxBytes] of [pcm], aligned to whole S16 samples.
  @visibleForTesting
  static Uint8List tailPcm(Uint8List pcm, int maxBytes) {
    if (pcm.lengthInBytes <= maxBytes) return pcm;
    var start = pcm.lengthInBytes - maxBytes;
    if (start.isOdd) start--;
    return Uint8List.sublistView(pcm, start);
  }

  /// Cancel any active capture and release resources (keeps the AEC module).
  void dispose() {
    _startGen++; // supersede any in-flight start()
    unawaited(_ampSub?.cancel());
    _ampSub = null;
    final recorder = _recorder;
    final path = _path;
    _recorder = null;
    _path = null;
    unawaited(_teardownRecordPackage(recorder, path));

    unawaited(_pcmSub?.cancel());
    _pcmSub = null;
    _capture?.kill(ProcessSignal.sigint);
    _capture = null;
    _pcm.clear();
  }

  /// Full teardown for when Talk Mode closes: stops capture and unloads the
  /// PipeWire echo-cancel module.
  void shutdown() {
    _isShutdown = true;
    dispose();
    _aec.dispose();
  }

  // -- subprocess backend (Linux) -------------------------------------------

  Future<void> _startSubprocess(void Function(double db) onDb) async {
    final gen = _startGen;
    final aecReady = await _aec.ensureLoaded();
    if (gen != _startGen) return; // superseded during AEC load
    _echoCancelActive = aecReady;

    final (exe, args) = aecReady
        ? (
            'pw-record',
            [
              '--raw',
              '--target',
              PipewireEchoCancel.sourceName,
              '--rate',
              '$_sampleRate',
              '--channels',
              '$_channels',
              '--format',
              's16',
              '-',
            ],
          )
        : (
            'arecord',
            [
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
            ],
          );

    final Process proc;
    try {
      proc = await Process.start(exe, args);
    } catch (e) {
      throw VoiceRecordingException('Failed to start recording: $e');
    }
    // Superseded (disposed/shutdown) while spawning — don't leak the process.
    if (gen != _startGen) {
      proc.kill(ProcessSignal.sigint);
      return;
    }
    _capture = proc;
    _pcm.clear();
    _levelRemainder = Uint8List(0);
    _pcmSub = proc.stdout.listen((chunk) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      _pcm.add(bytes);
      _emitLevels(bytes, onDb);
    }, onError: (Object e) => debugPrint('TalkRecorder capture error: $e'));
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

  Future<VoiceRecordingResult?> _stopSubprocess() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    _capture?.kill(ProcessSignal.sigint);
    await _capture?.exitCode;
    _capture = null;

    final pcm = _pcm.takeBytes();
    if (pcm.isEmpty) return null;
    final wav = wrapPcmInWav(pcm, sampleRate: _sampleRate, channels: _channels);
    final result = await AudioService.instance.transcribeAudio(wav, 'talk.wav');
    return VoiceRecordingResult(
      transcript: result.text,
      language: result.language,
    );
  }

  // -- record-package backend (mobile / web / macOS / Windows) ---------------

  Future<void> _startRecordPackage(void Function(double db) onDb) async {
    final gen = _startGen;
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      throw const VoiceRecordingException('Microphone permission denied');
    }
    if (gen != _startGen) {
      await recorder.dispose();
      return; // superseded during permission check
    }
    _path =
        '${Directory.systemTemp.path}/garbanzo_talk_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: _sampleRate,
          numChannels: _channels,
          // Mobile OSes provide hardware acoustic echo cancellation; enabling
          // it lets voice barge-in work over the speaker without self-triggering.
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: _path!,
      );
    } catch (e) {
      await recorder.dispose();
      _path = null;
      throw VoiceRecordingException('Failed to start recording: $e');
    }
    if (gen != _startGen) {
      await recorder.dispose();
      return; // superseded while starting
    }
    // Trust hardware AEC on phones; desktop record backends don't reliably AEC.
    _echoCancelActive = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
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
      final result = await AudioService.instance.transcribeAudio(
        audioBytes,
        path.split('/').last,
      );
      return VoiceRecordingResult(
        transcript: result.text,
        language: result.language,
      );
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
