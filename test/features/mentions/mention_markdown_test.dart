import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_markdown.dart';

void main() {
  group('mentionedToolNames', () {
    const tools = ['web_search', 'app_help', 'memories'];

    test('finds word-start #tokens for known tools only', () {
      expect(
        mentionedToolNames('use #web_search and #unknown here', tools),
        ['web_search'],
      );
    });

    test('matches at start of text and before punctuation', () {
      expect(mentionedToolNames('#app_help?', tools), ['app_help']);
    });

    test('ignores mid-word hashes and partial names', () {
      expect(mentionedToolNames('c#web_search #web', tools), isEmpty);
    });

    test('deduplicates and keeps tool-list order', () {
      expect(
        mentionedToolNames('#memories then #web_search then #memories', tools),
        ['web_search', 'memories'],
      );
    });
  });

  group('appendToolHint', () {
    test('appends a hint naming the tools', () {
      expect(
        appendToolHint('find it', ['web_search']),
        'find it\n\n(Please use the `web_search` tool for this.)',
      );
      expect(
        appendToolHint('go', ['a', 'b']),
        'go\n\n(Please use the `a`, `b` tools for this.)',
      );
    });

    test('returns the text unchanged with no mentions', () {
      expect(appendToolHint('hello', const []), 'hello');
    });
  });

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
