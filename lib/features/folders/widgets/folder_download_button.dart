import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_feedback.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Accept only successful virtual_folders download results. Persisted tool
/// results may be structured JSON or serialized JSON, depending on transport.
Map<String, dynamic>? folderDownloadResult(String toolName, Object? result) {
  if (toolName != 'virtual_folders') return null;
  if (result is String) {
    try {
      result = jsonDecode(result);
    } on FormatException {
      return null;
    }
  }
  if (result is! Map ||
      result['ok'] != true ||
      result['action'] != 'download') {
    return null;
  }
  final download = result['download'];
  if (download is! Map ||
      download['folder_id'] is! String ||
      download['filename'] is! String ||
      download['media_type'] is! String) {
    return null;
  }
  if ((download['folder_id'] as String).isEmpty ||
      (download['filename'] as String).isEmpty) {
    return null;
  }
  if (download['file_id'] != null && download['file_id'] is! String) {
    return null;
  }
  return Map<String, dynamic>.from(download);
}

class FolderDownloadButton extends StatefulWidget {
  const FolderDownloadButton({super.key, required this.download, this.service});
  final Map<String, dynamic> download;
  final FoldersService? service;
  @override
  State<FolderDownloadButton> createState() => _FolderDownloadButtonState();
}

class _FolderDownloadButtonState extends State<FolderDownloadButton> {
  bool _busy = false;
  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      await (widget.service ?? FoldersService()).download(
        folderId: widget.download['folder_id'] as String,
        fileId: widget.download['file_id'] as String?,
        filename: widget.download['filename'] as String,
        mediaType: widget.download['media_type'] as String,
        title: AppLocalizations.of(context)!.foldersDownload,
      );
    } catch (e) {
      if (mounted) folderError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _busy ? null : _download,
    icon: _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.download_outlined),
    label: Text(
      '${AppLocalizations.of(context)!.foldersDownload}: ${widget.download['filename']}',
    ),
  );
}
