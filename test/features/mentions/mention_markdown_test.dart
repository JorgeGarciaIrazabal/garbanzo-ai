import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_markdown.dart';

void main() {
  group('boldMentionTokens', () {
    test('bolds a mention at the start and mid-text', () {
      expect(
        boldMentionTokens('@Ana hi, ping @Scribe now'),
        '**@Ana** hi, ping **@Scribe** now',
      );
    });

    test('keeps trailing punctuation outside the bold', () {
      expect(boldMentionTokens('hey @Ana, hi'), 'hey **@Ana**, hi');
      expect(boldMentionTokens('(cc @Bob)'), '(cc **@Bob**)');
    });

    test('ignores mid-word @ (emails stay untouched)', () {
      expect(
        boldMentionTokens('mail me at ana@example.com'),
        'mail me at ana@example.com',
      );
    });

    test('a bare @ is left alone', () {
      expect(boldMentionTokens('just an @ sign'), 'just an @ sign');
    });

    test('already-bold mentions are not double-wrapped', () {
      expect(boldMentionTokens('**@Ana** hi'), '**@Ana** hi');
    });

    test('standalone email mention is bolded whole', () {
      expect(
        boldMentionTokens('ping @ana@example.com please'),
        'ping **@ana@example.com** please',
      );
    });
  });
}
