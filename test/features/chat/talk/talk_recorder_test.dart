import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_recorder.dart';

Uint8List _pcmFromSamples(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('TalkRecorder.rmsDbfs', () {
    test('empty input returns the silence floor', () {
      expect(TalkRecorder.rmsDbfs(Uint8List(0)), -160);
    });

    test('all-zero PCM returns the silence floor', () {
      expect(TalkRecorder.rmsDbfs(_pcmFromSamples([0, 0, 0, 0])), -160);
    });

    test('full-scale samples are ~0 dBFS', () {
      final pcm = _pcmFromSamples(List.filled(64, 32767));
      expect(TalkRecorder.rmsDbfs(pcm), closeTo(0, 0.1));
    });

    test('half-scale samples are ~-6 dBFS', () {
      final pcm = _pcmFromSamples(List.filled(64, 16384));
      expect(TalkRecorder.rmsDbfs(pcm), closeTo(-6.02, 0.2));
    });
  });

  group('TalkRecorder.wrapPcmInWav', () {
    test('prepends a 44-byte PCM WAV header', () {
      final pcm = _pcmFromSamples([1, 2, 3, 4]);
      final wav = TalkRecorder.wrapPcmInWav(
        pcm,
        sampleRate: 16000,
        channels: 1,
      );
      expect(wav.length, 44 + pcm.length);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final header = ByteData.sublistView(wav);
      expect(header.getUint16(22, Endian.little), 1); // channels
      expect(header.getUint32(24, Endian.little), 16000); // sample rate
      expect(header.getUint16(34, Endian.little), 16); // bits per sample
      expect(header.getUint32(40, Endian.little), pcm.length); // data size
    });
  });
}
