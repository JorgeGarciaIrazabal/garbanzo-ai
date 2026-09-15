import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/services/clipboard_image_reader.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';

void main() {
  tearDown(() => ClipboardImageReader.debugOverride = null);

  group('ClipboardImageReader.readImages', () {
    test('returns the image the platform clipboard provides', () async {
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      ClipboardImageReader.debugOverride = () async => [
        (name: 'pasted_20260101_120000.png', bytes: bytes),
      ];

      final images = await ClipboardImageReader.readImages();

      expect(images, hasLength(1));
      expect(images.single.bytes, bytes);
      expect(images.single.name, endsWith('.png'));
    });

    test('returns empty when the clipboard holds no image', () async {
      ClipboardImageReader.debugOverride = () async => const [];

      expect(await ClipboardImageReader.readImages(), isEmpty);
    });
  });

  group('FilePickerHelper.pasteImage', () {
    test('a pasted image is validated into a stageable image attachment',
        () async {
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      ClipboardImageReader.debugOverride = () async => [
        (name: 'pasted_20260101_120000.png', bytes: bytes),
      ];

      final result = await FilePickerHelper.pasteImage(existingNames: {});

      expect(result, isNotNull);
      expect(result!.rejected, isEmpty);
      expect(result.validationErrors, isEmpty);
      expect(result.added, hasLength(1));
      final attachment = result.added.single;
      expect(attachment.name, 'pasted_20260101_120000.png');
      expect(attachment.mimeType, 'image/png');
      expect(attachment.isImage, isTrue);
      expect(attachment.bytes, bytes);
    });

    test('returns null so the composer falls back to pasting text', () async {
      ClipboardImageReader.debugOverride = () async => const [];

      expect(await FilePickerHelper.pasteImage(existingNames: {}), isNull);
    });

    test('a pasted image colliding with a staged name is reported, not staged',
        () async {
      ClipboardImageReader.debugOverride = () async => [
        (
          name: 'pasted_20260101_120000.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ];

      final result = await FilePickerHelper.pasteImage(
        existingNames: {'pasted_20260101_120000.png'},
      );

      expect(result!.added, isEmpty);
      expect(result.validationErrors, [
        'Duplicate file: pasted_20260101_120000.png',
      ]);
    });
  });
}
