import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../models/chat_attachment.dart';

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

/// Handles file picking, validation, and MIME type inference.
class FilePickerHelper {
  /// Open the file picker and validate selected files.
  /// [existingNames] is used to detect duplicate filenames.
  static Future<FilePickResult?> pickFiles({
    required Set<String> existingNames,
  }) async {
    final result = await FilePicker.platform.pickFiles(
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

    final added = <ChatAttachment>[];
    final rejected = <String>[];
    final validationErrors = <String>[];

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;

      final mime = inferMime(file.name, bytes);
      final isImage = mime.startsWith('image/');
      final isPdf = mime == 'application/pdf';
      final isSpreadsheet = mime.endsWith('spreadsheetml.sheet') ||
          mime == 'application/vnd.ms-excel' ||
          mime == 'application/vnd.oasis.opendocument.spreadsheet' ||
          file.name.toLowerCase().endsWith('.csv') ||
          file.name.toLowerCase().endsWith('.xlsx') ||
          file.name.toLowerCase().endsWith('.xls') ||
          file.name.toLowerCase().endsWith('.ods');

      final maxBytes = isImage
          ? 5 * 1024 * 1024
          : isPdf
              ? 20 * 1024 * 1024
              : isSpreadsheet
                  ? 10 * 1024 * 1024
                  : 10 * 1024 * 1024;

      if (bytes.length > maxBytes) {
        rejected.add(
          '${file.name} (${formatBytes(bytes.length)} - max ${formatBytes(maxBytes)})',
        );
        continue;
      }

      if (existingNames.contains(file.name)) {
        validationErrors.add('Duplicate file: ${file.name}');
        continue;
      }

      added.add(ChatAttachment.fromPicked(
        name: file.name,
        mimeType: mime,
        bytes: bytes,
      ));
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
