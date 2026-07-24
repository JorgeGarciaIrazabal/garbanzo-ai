import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_tts_queue.dart';

void main() {
  test('uses MP3 for the Android-compatible playback path', () {
    expect(TalkTtsQueue.audioFormat, 'mp3');
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
