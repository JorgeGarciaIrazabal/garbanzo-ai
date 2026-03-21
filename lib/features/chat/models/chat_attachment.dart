import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_attachment.freezed.dart';

/// Categories of attachable files.
enum AttachmentType { image, document }

/// A file the user has selected to attach to a chat message.
@Freezed(toJson: false, fromJson: false)
class ChatAttachment with _$ChatAttachment {
  const ChatAttachment._();

  const factory ChatAttachment({
    required String name,
    required String mimeType,
    required AttachmentType type,
    required Uint8List bytes,
  }) = _ChatAttachment;

  bool get isImage => type == AttachmentType.image;
  bool get isDocument => type == AttachmentType.document;

  /// Base64-encoded bytes (used when sending images to the backend).
  String get base64Data => base64Encode(bytes);

  /// Decoded text (used for document attachments).
  String get textData => utf8.decode(bytes, allowMalformed: true);

  /// Serialise to the JSON shape the backend expects.
  Map<String, dynamic> toJson() => {
        'name': name,
        'mime_type': mimeType,
        'type': type.name,
        'data': isImage ? base64Data : textData,
      };

  static AttachmentType _typeFromMime(String mime) {
    if (mime.startsWith('image/')) return AttachmentType.image;
    return AttachmentType.document;
  }

  factory ChatAttachment.fromPicked({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) {
    return ChatAttachment(
      name: name,
      mimeType: mimeType,
      type: _typeFromMime(mimeType),
      bytes: bytes,
    );
  }
}
