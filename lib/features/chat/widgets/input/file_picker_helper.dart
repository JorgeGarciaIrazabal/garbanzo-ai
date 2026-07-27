import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';

/// Result of a file picking operation.
class FilePickResult {
  const FilePickResult({
    required this.added,
    required this.rejected,
    required this.validationErrors,
  });

  final List<ChatAttachment> added;
  final List<String> rejected;
  final List<String> validationErrors;
}

/// A raw file (name + bytes) awaiting validation. Used by callers that get
/// files from somewhere other than the picker (e.g. drag-and-drop).
typedef RawPickedFile = ({String name, Uint8List bytes});

/// Handles file picking, validation, and MIME type inference.
class FilePickerHelper {
  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];

  /// Camera photos and gallery picks are downscaled/re-encoded to stay well
  /// under the 5 MB image attachment limit.
  static const _maxImageDimension = 2048.0;
  static const _imageQuality = 85;

  /// Whether the running platform is a phone/tablet where the device camera
  /// and native photo picker make sense. On the web, [defaultTargetPlatform]
  /// reflects the underlying OS, so mobile browsers count too.
  static bool get isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Capture a photo with the device camera. Mobile platforms only
  /// (see [isMobilePlatform]).
  static Future<FilePickResult?> takePhoto({
    required Set<String> existingNames,
  }) async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: _maxImageDimension,
      maxHeight: _maxImageDimension,
      imageQuality: _imageQuality,
    );
    if (photo == null) return null;

    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final name =
        'photo_${now.year}${pad(now.month)}${pad(now.day)}'
        '_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}.jpg';

    return validate(
      files: [(name: name, bytes: await photo.readAsBytes())],
      existingNames: existingNames,
    );
  }

  /// Pick images only: the native photo picker on mobile, the file picker
  /// restricted to image extensions everywhere else.
  static Future<FilePickResult?> pickImages({
    required Set<String> existingNames,
  }) async {
    if (isMobilePlatform) {
      final photos = await ImagePicker().pickMultiImage(
        maxWidth: _maxImageDimension,
        maxHeight: _maxImageDimension,
        imageQuality: _imageQuality,
      );
      if (photos.isEmpty) return null;
      return validate(
        files: [
          for (final photo in photos)
            (name: photo.name, bytes: await photo.readAsBytes()),
        ],
        existingNames: existingNames,
      );
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: _imageExtensions,
    );
    if (result == null) return null;

    return validate(
      files: [
        for (final file in result.files)
          if (file.bytes != null) (name: file.name, bytes: file.bytes!),
      ],
      existingNames: existingNames,
    );
  }

  /// Open the file picker and validate selected files.
  /// [existingNames] is used to detect duplicate filenames.
  static Future<FilePickResult?> pickFiles({
    required Set<String> existingNames,
  }) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        // images
        ..._imageExtensions,
        // documents
        'txt', 'md', 'csv', 'json', 'xml', 'yaml', 'yml',
        'html', 'htm', 'css', 'js', 'ts', 'py', 'dart', 'rs',
        'go', 'java', 'kt', 'swift', 'c', 'cpp', 'h',
        'pdf', 'xlsx', 'xls', 'ods',
      ],
    );

    if (result == null) return null;

    return validate(
      files: [
        for (final file in result.files)
          if (file.bytes != null) (name: file.name, bytes: file.bytes!),
      ],
      existingNames: existingNames,
    );
  }

  /// Validate raw files against size limits and duplicate names.
  ///
  /// Single source of truth for attachment validation — shared by the file
  /// picker above and the chat page's drag-and-drop path.
  static FilePickResult validate({
    required Iterable<RawPickedFile> files,
    required Set<String> existingNames,
  }) {
    final added = <ChatAttachment>[];
    final rejected = <String>[];
    final validationErrors = <String>[];
    final seenNames = {...existingNames};

    for (final file in files) {
      final bytes = file.bytes;
      final name = file.name;
      final mime = inferMime(name, bytes);
      final isImage = mime.startsWith('image/');
      final isPdf = mime == 'application/pdf';
      final isSpreadsheet =
          mime.endsWith('spreadsheetml.sheet') ||
          mime == 'application/vnd.ms-excel' ||
          mime == 'application/vnd.oasis.opendocument.spreadsheet' ||
          name.toLowerCase().endsWith('.csv') ||
          name.toLowerCase().endsWith('.xlsx') ||
          name.toLowerCase().endsWith('.xls') ||
          name.toLowerCase().endsWith('.ods');

      final maxBytes = isImage
          ? 5 * 1024 * 1024
          : isPdf
          ? 20 * 1024 * 1024
          : isSpreadsheet
          ? 10 * 1024 * 1024
          : 10 * 1024 * 1024;

      if (bytes.length > maxBytes) {
        rejected.add(
          '$name (${formatBytes(bytes.length)} - max ${formatBytes(maxBytes)})',
        );
        continue;
      }

      if (seenNames.contains(name)) {
        validationErrors.add('Duplicate file: $name');
        continue;
      }

      added.add(
        ChatAttachment.fromPicked(name: name, mimeType: mime, bytes: bytes),
      );
      seenNames.add(name);
    }

    return FilePickResult(
      added: added,
      rejected: rejected,
      validationErrors: validationErrors,
    );
  }

  static String inferMime(String filename, Uint8List bytes) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xml')) return 'application/xml';
    return 'text/plain';
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
