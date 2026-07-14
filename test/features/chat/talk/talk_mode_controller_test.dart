import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_mode_controller.dart';

void main() {
  group('TalkModeController.lastSentenceBoundary', () {
    test('returns the offset when no complete sentence yet', () {
      // No terminator+whitespace after the cursor.
      expect(TalkModeController.lastSentenceBoundary('Hello ther', 0), 0);
    });

    test('cuts just after the last completed sentence', () {
      const text = 'One. Two. Thr';
      final cut = TalkModeController.lastSentenceBoundary(text, 0);
      expect(text.substring(0, cut), 'One. Two.');
    });

    test('does not re-report sentences already spoken', () {
      const text = 'One. Two. Three.';
      // Already spoke up to just after "One."
      final cut = TalkModeController.lastSentenceBoundary(text, 4);
      expect(text.substring(4, cut).trim(), 'Two.');
    });

    test('handles ? and ! terminators', () {
      const text = 'Really? Yes! And';
      final cut = TalkModeController.lastSentenceBoundary(text, 0);
      expect(text.substring(0, cut), 'Really? Yes!');
    });

    test('a trailing sentence without following whitespace is not yet cut', () {
      // "Done." has no trailing space, so it is still considered in-progress
      // until more text (or the stream end) arrives.
      expect(TalkModeController.lastSentenceBoundary('Done.', 0), 0);
    });
  });
}
