import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_mode_controller.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';

void main() {
  group('TalkModeController.bargeForSensitivity', () {
    test('off yields no detector', () {
      expect(
        TalkModeController.bargeForSensitivity(BargeInSensitivity.off),
        isNull,
      );
    });

    test('higher sensitivity means a lower bar and a shorter stretch', () {
      final low = TalkModeController.bargeForSensitivity(
        BargeInSensitivity.low,
      )!;
      final normal = TalkModeController.bargeForSensitivity(
        BargeInSensitivity.normal,
      )!;
      final high = TalkModeController.bargeForSensitivity(
        BargeInSensitivity.high,
      )!;
      expect(high.marginDb, lessThan(normal.marginDb));
      expect(normal.marginDb, lessThan(low.marginDb));
      expect(high.requiredLoud, lessThan(normal.requiredLoud));
      expect(normal.requiredLoud, lessThan(low.requiredLoud));
    });
  });

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

  group('TalkModeController.resolveReplyLanguage', () {
    test('manual override always wins', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: 'fr',
          autoLanguage: true,
          detected: 'es',
          preferred: const ['es'],
        ),
        'fr',
      );
      // Even with auto off and nothing detected.
      expect(
        TalkModeController.resolveReplyLanguage(
          override: 'it',
          autoLanguage: false,
          detected: null,
          preferred: const [],
        ),
        'it',
      );
    });

    test('auto mode follows the detected language', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: 'es',
          preferred: const [],
        ),
        'es',
      );
    });

    test('auto off keeps the pinned voice (null)', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: false,
          detected: 'es',
          preferred: const [],
        ),
        isNull,
      );
    });

    test('nothing detected yields null', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: null,
          preferred: const ['es'],
        ),
        isNull,
      );
    });

    test('a non-empty preferred list bounds auto switching', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: 'fr',
          preferred: const ['en', 'es'],
        ),
        isNull,
      );
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: 'es',
          preferred: const ['en', 'es'],
        ),
        'es',
      );
    });
  });
}
