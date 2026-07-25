import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/utils/tts_text_chunks.dart';

void main() {
  test('groups short sentences without exceeding the limit', () {
    final chunks = splitTextForTts(
      'One short sentence. Another short sentence. A final sentence.',
      maxLength: 45,
    );

    expect(chunks, [
      'One short sentence. Another short sentence.',
      'A final sentence.',
    ]);
    expect(chunks.every((chunk) => chunk.length <= 45), isTrue);
  });

  test('hard-splits a long unpunctuated value', () {
    final text = List.filled(30, 'word').join(' ');
    final chunks = splitTextForTts(text, maxLength: 25);

    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => chunk.length <= 25), isTrue);
    expect(chunks.join(' '), text);
  });

  test('hard-splits a single word longer than the limit', () {
    final chunks = splitTextForTts('abcdefghijk', maxLength: 4);

    expect(chunks, ['abcd', 'efgh', 'ijk']);
  });

  test('returns no chunks for blank text', () {
    expect(splitTextForTts('   '), isEmpty);
  });
}
