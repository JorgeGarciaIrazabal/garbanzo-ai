import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_query.dart';

const _triggers = {'@', '/', '#'};

MentionQuery? _scan(String text, int cursor) =>
    activeMentionQuery(text, TextSelection.collapsed(offset: cursor), _triggers);

void main() {
  group('activeMentionQuery', () {
    test('detects a trigger at the start of the text', () {
      final q = _scan('@an', 3);
      expect(q, isNotNull);
      expect(q!.trigger, '@');
      expect(q.query, 'an');
      expect(q.start, 0);
      expect(q.end, 3);
    });

    test('detects a trigger after whitespace mid-text', () {
      final q = _scan('hello /con', 10);
      expect(q!.trigger, '/');
      expect(q.query, 'con');
      expect(q.start, 6);
    });

    test('a bare trigger yields an empty query', () {
      final q = _scan('hi #', 4);
      expect(q!.query, '');
    });

    test('query may contain further trigger chars (emails)', () {
      final q = _scan('@ana@example.com', 16);
      expect(q!.trigger, '@');
      expect(q.query, 'ana@example.com');
    });

    test('mid-word trigger does not fire', () {
      expect(_scan('email@example.com', 17), isNull);
    });

    test('cursor before the trigger does not fire', () {
      expect(_scan('@ana', 0), isNull);
    });

    test('cursor in a plain word does not fire', () {
      expect(_scan('hello world', 11), isNull);
    });

    test('whitespace between trigger and cursor ends the mention', () {
      expect(_scan('@ana lopez', 10), isNull);
    });

    test('cursor inside the token uses only the part before it', () {
      final q = _scan('@anabel', 4);
      expect(q!.query, 'ana');
      expect(q.end, 4);
    });

    test('non-collapsed selections never fire', () {
      expect(
        activeMentionQuery(
          '@ana',
          const TextSelection(baseOffset: 1, extentOffset: 3),
          _triggers,
        ),
        isNull,
      );
    });
  });

  group('insertMention', () {
    test('replaces the token, appends a space, and places the cursor', () {
      const value = TextEditingValue(
        text: 'hi @an there',
        selection: TextSelection.collapsed(offset: 6),
      );
      final query = activeMentionQuery(value.text, value.selection, _triggers)!;

      final out = insertMention(value, query, '@Ana');

      expect(out.text, 'hi @Ana  there');
      expect(out.selection.baseOffset, 8); // after "hi @Ana "
    });

    test('works at the end of the text', () {
      const value = TextEditingValue(
        text: '#we',
        selection: TextSelection.collapsed(offset: 3),
      );
      final query = activeMentionQuery(value.text, value.selection, _triggers)!;

      final out = insertMention(value, query, '#web_search');

      expect(out.text, '#web_search ');
      expect(out.selection.baseOffset, 12);
    });
  });
}
