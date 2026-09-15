import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:garbanzo_ai/core/platform_info.dart';

/// Delivers an exported file through the platform's natural export surface:
/// Save As on desktop, share/download elsewhere.
///
/// Every export in the app (research reports, chat and room transcripts) goes
/// through here so "what does Download do" has exactly one answer per platform.
class ExportDownloader {
  const ExportDownloader();

  Future<void> downloadMarkdown({
    required String markdown,
    required String filename,
    required String title,
  }) {
    return downloadBytes(
      bytes: Uint8List.fromList(utf8.encode(markdown)),
      filename: filename,
      title: title,
      mimeType: 'text/markdown',
    );
  }

  Future<void> downloadBytes({
    required Uint8List bytes,
    required String filename,
    required String title,
    required String mimeType,
  }) async {
    if (PlatformInfo.isDesktop) {
      await FilePicker.saveFile(
        dialogTitle: title,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: [_extensionOf(filename)],
        bytes: bytes,
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        title: title,
        files: [XFile.fromData(bytes, mimeType: mimeType)],
        fileNameOverrides: [filename],
      ),
    );
  }

  /// `chat-notes.docx` → `docx`; empty string when there is no extension
  /// (file_picker rejects an empty entry in `allowedExtensions`).
  static String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1);
  }
}
