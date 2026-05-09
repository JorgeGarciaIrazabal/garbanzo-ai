import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/utils/text_cleaner.dart';

void main() {
  group('cleanTextForSpeech', () {
    test('strips fenced code blocks entirely', () {
      const input = 'Intro\n```dart\nvoid main() {}\n```\nOutro';
      expect(cleanTextForSpeech(input), 'Intro\n\nOutro');
    });

    test('unwraps inline code backticks', () {
      expect(cleanTextForSpeech('use `foo` to run'), 'use foo to run');
    });

    test('converts image markdown to alt text', () {
      expect(
        cleanTextForSpeech('![logo](https://example.com/x.png)'),
        'logo',
      );
    });

    test('converts link markdown to text', () {
      expect(
        cleanTextForSpeech('see [docs](https://example.com)'),
        'see docs',
      );
    });

    test('strips markdown headings', () {
      expect(
        cleanTextForSpeech('# Title\n## Sub\nBody'),
        'Title\nSub\nBody',
      );
    });

    test('removes bold/italic/strike markers', () {
      expect(
        cleanTextForSpeech('**bold** and *italic* and ~~strike~~'),
        'bold and italic and strike',
      );
    });

    test('strips bullet and numbered list markers', () {
      final out = cleanTextForSpeech('- one\n- two\n\n1. first\n2. second');
      expect(out.contains('one'), isTrue);
      expect(out.contains('two'), isTrue);
      expect(out.contains('first'), isTrue);
      expect(out.contains('second'), isTrue);
      expect(out.contains('-'), isFalse, reason: 'bullets should be gone');
      expect(RegExp(r'\d+\.').hasMatch(out), isFalse,
          reason: 'numbered prefixes should be gone');
    });

    test('strips blockquote and horizontal rule markers', () {
      expect(
        cleanTextForSpeech('> quoted text\n\n---\n\nend'),
        'quoted text\n\nend',
      );
    });

    test('strips HTML tags', () {
      expect(
        cleanTextForSpeech('<b>bold</b> and <i>italic</i>'),
        'bold and italic',
      );
    });

    test('strips common emojis', () {
      expect(cleanTextForSpeech('Hello 👋 world 🚀!'), 'Hello world !');
    });

    test('collapses excessive whitespace', () {
      expect(cleanTextForSpeech('a    b\n\n\n\nc'), 'a b\n\nc');
    });

    test('trims the result', () {
      expect(cleanTextForSpeech('\n\n hi \n\n'), 'hi');
    });

    test('returns empty string for empty input', () {
      expect(cleanTextForSpeech(''), '');
    });

    test('preserves plain text untouched', () {
      expect(
        cleanTextForSpeech('Plain sentence with no markdown.'),
        'Plain sentence with no markdown.',
      );
    });
  });
}
