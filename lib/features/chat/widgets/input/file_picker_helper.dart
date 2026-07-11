import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

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
        'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
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

      if (existingNames.contains(name)) {
        validationErrors.add('Duplicate file: $name');
        continue;
      }

      added.add(
        ChatAttachment.fromPicked(name: name, mimeType: mime, bytes: bytes),
      );
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
