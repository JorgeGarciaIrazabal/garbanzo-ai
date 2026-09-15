import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/services/transcript_export_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Callback for "download this transcript in the chosen format".
typedef TranscriptDownloadCallback =
    void Function(TranscriptExportFormat format);

/// Asks which format to download a transcript as.
///
/// A menu with a format submenu is awkward on touch, and Pin/Download/Delete
/// read best as three peer items, so the format lives one step past the row
/// menu: pick "Download transcript", then pick the format.
Future<TranscriptExportFormat?> showTranscriptFormatSheet(
  BuildContext context,
) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<TranscriptExportFormat>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.labelDownloadTranscript,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('transcript_format_docx'),
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.labelDownloadAsDocx),
            onTap: () => Navigator.of(context).pop(TranscriptExportFormat.docx),
          ),
          ListTile(
            key: const ValueKey('transcript_format_markdown'),
            leading: const Icon(Icons.article_outlined),
            title: Text(l10n.labelDownloadAsMarkdown),
            onTap: () =>
                Navigator.of(context).pop(TranscriptExportFormat.markdown),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
