import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';

void main() {
  group('ChatAttachment', () {
    test('fromPicked detects image type from MIME', () {
      final att = ChatAttachment.fromPicked(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(att.type, AttachmentType.image);
      expect(att.isImage, true);
      expect(att.isDocument, false);
    });

    test('fromPicked detects document type from non-image MIME', () {
      final att = ChatAttachment.fromPicked(
        name: 'readme.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(utf8.encode('hello world')),
      );
      expect(att.type, AttachmentType.document);
      expect(att.isDocument, true);
      expect(att.isImage, false);
    });

    test('toJson for image produces base64 data', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final att = ChatAttachment(
        name: 'img.png',
        mimeType: 'image/png',
        type: AttachmentType.image,
        bytes: bytes,
      );
      final json = att.toJson();
      expect(json['name'], 'img.png');
      expect(json['mime_type'], 'image/png');
      expect(json['type'], 'image');
      expect(json['encoding'], 'base64');
      expect(json['data'], base64Encode(bytes));
    });

    test('toJson for document preserves binary and Unicode bytes as base64', () {
      final bytes = Uint8List.fromList([
        ...utf8.encode('HÉBRIDAS, España'),
        0,
        255,
      ]);
      final att = ChatAttachment(
        name: 'CONTRATO ISLAS HÉBRIDAS 70.pdf',
        mimeType: 'application/pdf',
        type: AttachmentType.document,
        bytes: bytes,
      );
      final json = att.toJson();
      expect(json['type'], 'document');
      expect(json['encoding'], 'base64');
      expect(base64Decode(json['data'] as String), bytes);
    });
  });
}
