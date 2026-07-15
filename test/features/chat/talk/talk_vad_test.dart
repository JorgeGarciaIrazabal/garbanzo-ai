import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_vad.dart';

void main() {
  group('TalkVad', () {
    late DateTime t;
    setUp(() => t = DateTime(2026, 1, 1, 12));

    DateTime at(int ms) => t.add(Duration(milliseconds: ms));

    test('reports speechStart when level crosses the start threshold', () {
      final vad = TalkVad();
      expect(vad.update(-50, at(0)), VadEvent.none); // quiet
      expect(vad.update(-20, at(100)), VadEvent.speechStart); // loud
      expect(vad.isSpeaking, isTrue);
    });

    test('reports speechEnd after sustained silence', () {
      final vad = TalkVad(
        silenceDuration: const Duration(milliseconds: 1000),
        minSpeechDuration: const Duration(milliseconds: 300),
      );
      expect(vad.update(-20, at(0)), VadEvent.speechStart);
      expect(vad.update(-20, at(400)), VadEvent.none); // still talking
      expect(vad.update(-50, at(500)), VadEvent.none); // silence begins
      expect(vad.update(-50, at(1200)), VadEvent.none); // <1s of silence
      expect(vad.update(-50, at(1600)), VadEvent.speechEnd); // >=1s of silence
      expect(vad.isSpeaking, isFalse);
    });

    test('does not end on a brief dip below the silence threshold', () {
      final vad = TalkVad(silenceDuration: const Duration(milliseconds: 1000));
      vad.update(-20, at(0)); // start
      vad.update(-50, at(400)); // brief quiet
      expect(vad.update(-20, at(600)), VadEvent.none); // loud again resets
      expect(vad.update(-50, at(1000)), VadEvent.none); // silence restarts
      expect(vad.update(-50, at(1400)), VadEvent.none); // only 400ms silent
    });

    test('ignores a blip shorter than minSpeechDuration', () {
      final vad = TalkVad(
        silenceDuration: const Duration(milliseconds: 200),
        minSpeechDuration: const Duration(milliseconds: 500),
      );
      expect(vad.update(-20, at(0)), VadEvent.speechStart);
      // Silent long enough, but total speech (250ms) < minSpeechDuration.
      expect(vad.update(-50, at(50)), VadEvent.none);
      expect(vad.update(-50, at(250)), VadEvent.none);
    });

    test('reset re-arms the detector', () {
      final vad = TalkVad();
      vad.update(-20, at(0));
      vad.reset();
      expect(vad.isSpeaking, isFalse);
      expect(vad.update(-20, at(100)), VadEvent.speechStart);
    });
  });
}
