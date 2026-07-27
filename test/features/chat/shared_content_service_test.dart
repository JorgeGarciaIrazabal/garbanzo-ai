import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/services/shared_content_service.dart';

void main() {
  group('SharedContent.fromPlatform', () {
    test('parses files and accompanying text', () {
      final content = SharedContent.fromPlatform({
        'files': [
          {
            'name': 'photo.png',
            'bytes': Uint8List.fromList([1, 2, 3]),
          },
        ],
        'text': 'Look at this',
      });

      expect(content.text, 'Look at this');
      expect(content.files, hasLength(1));
      expect(content.files.single.name, 'photo.png');
      expect(content.files.single.bytes, [1, 2, 3]);
      expect(content.isEmpty, isFalse);
    });

    test('ignores malformed platform values', () {
      final content = SharedContent.fromPlatform({
        'files': [
          {'name': null, 'bytes': 'not bytes'},
        ],
      });

      expect(content.files, isEmpty);
      expect(content.isEmpty, isTrue);
    });

    test('accepts integer lists from the standard message codec', () {
      final content = SharedContent.fromPlatform({
        'files': [
          {
            'name': 'notes.txt',
            'bytes': <int>[65, 66],
          },
        ],
      });

      expect(content.files.single.bytes, [65, 66]);
    });
  });
}
