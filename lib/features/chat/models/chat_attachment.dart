import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_attachment.freezed.dart';

/// Categories of attachable files.
enum AttachmentType { image, document }

/// A file the user has selected to attach to a chat message.
@Freezed(toJson: false, fromJson: false)
abstract class ChatAttachment with _$ChatAttachment {
  const ChatAttachment._();

  const factory ChatAttachment({
    required String name,
    required String mimeType,
    required AttachmentType type,
    required Uint8List bytes,
  }) = _ChatAttachment;

  bool get isImage => type == AttachmentType.image;
  bool get isDocument => type == AttachmentType.document;

  /// Whether this attachment has actual file data (false for reloaded messages).
  bool get hasBytes => bytes.isNotEmpty;

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

  /// Reconstruct from the metadata stored in [Message.meta['attachments']].
  ///
  /// Images carry their (server-downscaled) base64 data so they can still be
  /// rendered after a reload; documents are name-only — their text was
  /// appended to the message content server-side.
  factory ChatAttachment.fromMetadata(Map<String, dynamic> json) {
    final mimeType = json['mime_type'] as String? ?? 'application/octet-stream';
    final data = json['data'];
    return ChatAttachment(
      name: json['name'] as String? ?? 'unknown',
      mimeType: mimeType,
      type: _typeFromMime(mimeType),
      bytes: data is String && data.isNotEmpty
          ? base64Decode(data)
          : Uint8List(0),
    );
  }
}
