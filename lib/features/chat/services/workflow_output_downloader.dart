import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:garbanzo_ai/core/platform_info.dart';

/// Delivers a research workflow's markdown report through the platform's
/// natural export surface: Save As on desktop, share/download elsewhere.
class WorkflowOutputDownloader {
  const WorkflowOutputDownloader();

  Future<void> download({
    required String markdown,
    required String filename,
    required String title,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(markdown));
    if (PlatformInfo.isDesktop) {
      await FilePicker.saveFile(
        dialogTitle: title,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: const ['md'],
        bytes: bytes,
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        title: title,
        files: [XFile.fromData(bytes, mimeType: 'text/markdown')],
        fileNameOverrides: [filename],
      ),
    );
  }
}
