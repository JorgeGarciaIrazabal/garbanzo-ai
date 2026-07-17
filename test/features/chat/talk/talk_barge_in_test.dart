import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_barge_in.dart';

void main() {
  group('TalkBargeIn', () {
    test('fires after enough sustained loud samples', () {
      final barge = TalkBargeIn()..arm(-50); // threshold −32
      for (var i = 0; i < 5; i++) {
        expect(barge.update(-20), isFalse);
      }
      expect(barge.update(-20), isTrue); // 6th loud of 6
    });

    test('a brief dip does not reset progress (sliding window)', () {
      final barge = TalkBargeIn()..arm(-50);
      for (var i = 0; i < 5; i++) {
        expect(barge.update(-20), isFalse);
      }
      expect(barge.update(-50), isFalse); // intra-word dip
      // The old strict consecutive-run would restart from zero here.
      expect(barge.update(-20), isTrue); // 6 loud within the last 7
    });

    test('scattered loud samples never fire', () {
      final barge = TalkBargeIn()..arm(-50);
      for (var i = 0; i < 20; i++) {
        // Alternating: at most 4 loud in any 8-sample window.
        expect(barge.update(i.isEven ? -20 : -50), isFalse);
      }
    });

    test('absolute gate ignores quiet sound over a very low floor', () {
      final barge = TalkBargeIn()..arm(-80); // floor+margin=−62, gate −45
      for (var i = 0; i < 20; i++) {
        // Above floor+margin but below the −45 dBFS gate: not the user.
        expect(barge.update(-50), isFalse);
      }
    });

    test('sustained residual echo raises the bar', () {
      final barge = TalkBargeIn()..arm(-60); // threshold starts at −42
      // Steady sub-threshold echo at −44 pulls the floor up toward it…
      for (var i = 0; i < 20; i++) {
        expect(barge.update(-44), isFalse);
      }
      expect(barge.floorDb, greaterThan(-46));
      // …so a level that beat the original threshold no longer counts.
      for (var i = 0; i < 10; i++) {
        expect(barge.update(-40), isFalse);
      }
    });

    test('window resets after firing', () {
      final barge = TalkBargeIn()..arm(-50);
      for (var i = 0; i < 6; i++) {
        barge.update(-20);
      }
      // A fresh full stretch is needed to fire again.
      for (var i = 0; i < 5; i++) {
        expect(barge.update(-20), isFalse);
      }
      expect(barge.update(-20), isTrue);
    });

    test('arm resets both the floor and the window', () {
      final barge = TalkBargeIn()..arm(-50);
      for (var i = 0; i < 5; i++) {
        barge.update(-20); // almost fired
      }
      barge.arm(-30);
      expect(barge.floorDb, -30);
      // Old progress is gone and the threshold moved up with the new floor.
      expect(barge.update(-20), isFalse);
    });
  });
}
