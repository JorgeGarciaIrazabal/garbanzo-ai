import 'package:garbanzo_ai/features/chat/services/export_downloader.dart';

/// Delivers a research workflow's markdown report.
///
/// Thin specialization of [ExportDownloader] so every export in the app — a
/// research report, a chat or room transcript — shares one implementation of
/// "Save As on desktop, share/download elsewhere".
class WorkflowOutputDownloader {
  const WorkflowOutputDownloader({
    ExportDownloader downloader = const ExportDownloader(),
  }) : _downloader = downloader;

  final ExportDownloader _downloader;

  Future<void> download({
    required String markdown,
    required String filename,
    required String title,
  }) {
    return _downloader.downloadMarkdown(
      markdown: markdown,
      filename: filename,
      title: title,
    );
  }
}
