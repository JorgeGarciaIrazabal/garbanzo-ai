import 'dart:async';
import 'dart:typed_data';

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

    test('groups short sentences into one request', () {
      final chunks = TalkTtsQueue.splitIntoChunks('One. Two. Three.');
      // All fit under the API limit, so they coalesce into a single chunk.
      expect(chunks.length, 1);
      expect(chunks.first, 'One. Two. Three.');
    });

    test('starts a new chunk once the API limit is exceeded', () {
      final long = List.filled(
        200,
        'A sentence that is fairly wordy.',
      ).join(' ');
      final chunks = TalkTtsQueue.splitIntoChunks(long.trim());
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.length <= 5000), isTrue);
    });

    test('returns empty for blank input', () {
      expect(TalkTtsQueue.splitIntoChunks('   '), isEmpty);
    });
  });

  test('prefetches text enqueued while the current chunk is playing', () async {
    final playbackStarted = Completer<void>();
    final finishPlayback = Completer<void>();
    final queueDrained = Completer<void>();
    final synthesized = <String>[];
    var playbackCount = 0;
    final queue = TalkTtsQueue(
      voice: 'af_heart',
      speed: 1,
      synthesizer: (chunk) async {
        synthesized.add(chunk);
        return Uint8List(1);
      },
      chunkPlayer: (_) async {
        playbackCount++;
        if (playbackCount == 1) {
          playbackStarted.complete();
          await finishPlayback.future;
        }
      },
      onComplete: queueDrained.complete,
    );

    queue.enqueue('First sentence.');
    await playbackStarted.future;
    queue.enqueue('Second sentence.');
    await Future<void>.delayed(Duration.zero);

    expect(synthesized, ['First sentence.', 'Second sentence.']);

    finishPlayback.complete();
    await queueDrained.future;
    expect(playbackCount, 2);
  });
}
