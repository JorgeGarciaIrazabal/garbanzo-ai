import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_vad.dart';

void main() {
  group('TalkVad (adaptive)', () {
    late DateTime t;
    setUp(() => t = DateTime(2026, 1, 1, 12));
    DateTime at(int ms) => t.add(Duration(milliseconds: ms));

    /// Feed a few quiet ambient samples so the detector finishes calibrating.
    void calibrate(TalkVad vad, {double db = -50}) {
      for (var i = 0; i < 3; i++) {
        vad.update(db, at(-30 + i * 10));
      }
    }

    test('speechStart when the level rises above the ambient floor', () {
      final vad = TalkVad();
      calibrate(vad);
      for (var i = 0; i < 2; i++) {
        expect(vad.update(-50, at(i * 100)), VadEvent.none); // quiet ambient
      }
      expect(vad.update(-20, at(600)), VadEvent.speechStart);
      expect(vad.isSpeaking, isTrue);
    });

    test('speechEnd after the level falls back to the floor for the window', () {
      final vad = TalkVad(
        silenceDuration: const Duration(milliseconds: 900),
        minSpeechDuration: const Duration(milliseconds: 300),
      );
      calibrate(vad); // establish floor ~-50
      expect(vad.update(-20, at(100)), VadEvent.speechStart);
      expect(vad.update(-20, at(500)), VadEvent.none); // still talking
      expect(vad.update(-50, at(600)), VadEvent.none); // silence begins
      expect(vad.update(-50, at(1000)), VadEvent.none); // <900ms silent
      expect(vad.update(-50, at(1550)), VadEvent.speechEnd); // >=900ms silent
      expect(vad.isSpeaking, isFalse);
    });

    test('adapts to a noisy room: quiet-ish sounds no longer trigger', () {
      final vad = TalkVad();
      for (var i = 0; i < 80; i++) {
        vad.update(-30, at(i * 100)); // loud ambient raises the floor
      }
      expect(vad.noiseFloorDb, greaterThan(-35));
      // A level that would have started speech in a quiet room is now ambient.
      expect(vad.update(-38, at(9000)), VadEvent.none);
      // A clearly-louder level still starts speech.
      expect(vad.update(-12, at(9100)), VadEvent.speechStart);
    });

    test('does not end on a brief dip below the speech level', () {
      final vad = TalkVad(silenceDuration: const Duration(milliseconds: 900));
      calibrate(vad);
      vad.update(-20, at(100)); // start
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
      calibrate(vad);
      expect(vad.update(-20, at(100)), VadEvent.speechStart);
      expect(vad.update(-50, at(150)), VadEvent.none);
      expect(vad.update(-50, at(360)), VadEvent.none); // silent 210ms, spoke 260
    });

    test('reset clears speech state but keeps the learned floor', () {
      final vad = TalkVad();
      for (var i = 0; i < 80; i++) {
        vad.update(-30, at(i * 100));
      }
      final floor = vad.noiseFloorDb;
      vad.update(-12, at(9000)); // speechStart
      vad.reset();
      expect(vad.isSpeaking, isFalse);
      expect(vad.noiseFloorDb, floor);
    });
  });
}
