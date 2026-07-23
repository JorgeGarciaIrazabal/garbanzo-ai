import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_recorder.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_tts_queue.dart';

void main() {
  group('TalkTtsQueue.prependWavSilence', () {
    test('adds aligned silence and preserves the original PCM samples', () {
      final pcm = Uint8List.fromList([1, 2, 3, 4]);
      final wav = TalkRecorder.wrapPcmInWav(
        pcm,
        sampleRate: 24000,
        channels: 1,
      );

      final padded = TalkTtsQueue.prependWavSilence(
        wav,
        TalkTtsQueue.playbackPreroll,
      );

      const silenceBytes = 24000; // 500 ms × 24 kHz × 16-bit mono.
      final header = ByteData.sublistView(padded);
      expect(padded.lengthInBytes, wav.lengthInBytes + silenceBytes);
      expect(header.getUint32(4, Endian.little), padded.lengthInBytes - 8);
      expect(header.getUint32(40, Endian.little), pcm.length + silenceBytes);
      expect(padded.sublist(44, 44 + silenceBytes), everyElement(0));
      expect(padded.sublist(44 + silenceBytes), pcm);
    });

    test('leaves invalid audio untouched', () {
      final invalid = Uint8List.fromList([1, 2, 3]);
      expect(
        TalkTtsQueue.prependWavSilence(invalid, const Duration(milliseconds: 500)),
        same(invalid),
      );
    });
  });

  group('TalkTtsQueue.splitIntoChunks', () {
    test('splits at sentence boundaries', () {
      final chunks = TalkTtsQueue.splitIntoChunks('Hello there. How are you?');
      expect(chunks, ['Hello there. How are you?']);
    });

    test('groups short sentences up to the target size', () {
      final chunks = TalkTtsQueue.splitIntoChunks('One. Two. Three.');
      // All well under 500 chars, so they coalesce into a single chunk.
      expect(chunks.length, 1);
      expect(chunks.first, 'One. Two. Three.');
    });

    test('starts a new chunk once the target size is exceeded', () {
      final long = 'A sentence that is fairly wordy. ' * 30; // > 500 chars
      final chunks = TalkTtsQueue.splitIntoChunks(long.trim());
      expect(chunks.length, greaterThan(1));
    });

    test('returns empty for blank input', () {
      expect(TalkTtsQueue.splitIntoChunks('   '), isEmpty);
    });
  });
}
