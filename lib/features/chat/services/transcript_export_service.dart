import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/services/export_downloader.dart';

/// Formats a transcript can be downloaded as.
enum TranscriptExportFormat {
  /// A real Word document: a heading per turn, lists, code blocks, tables.
  docx,

  /// Plain markdown, for pasting into a note, issue, or wiki.
  markdown,
}

/// Fetches a conversation's or room's transcript and hands it to the platform's
/// save/share surface.
///
/// The server owns both the rendering and the filename (it sends
/// `Content-Disposition`), so this service stays a transport + delivery hop.
class TranscriptExportService {
  TranscriptExportService({ApiClient? api, ExportDownloader? downloader})
    : _api = api ?? ApiClient.instance,
      _downloader = downloader ?? const ExportDownloader();

  final ApiClient _api;
  final ExportDownloader _downloader;

  static const _docxMimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  Future<void> downloadConversation(
    String conversationId, {
    required TranscriptExportFormat format,
    required String title,
  }) {
    return _download(
      '/api/v1/chat/conversations/$conversationId/export',
      format: format,
      title: title,
      fallbackFilename: 'chat-$conversationId.${_extension(format)}',
    );
  }

  Future<void> downloadRoom(
    String roomId, {
    required TranscriptExportFormat format,
    required String title,
  }) {
    return _download(
      '/api/v1/rooms/$roomId/export',
      format: format,
      title: title,
      fallbackFilename: 'room-$roomId.${_extension(format)}',
    );
  }

  Future<void> _download(
    String path, {
    required TranscriptExportFormat format,
    required String title,
    required String fallbackFilename,
  }) async {
    final result = await _api.download('$path?format=${format.name}');
    await _downloader.downloadBytes(
      bytes: result.bytes,
      filename: result.filename ?? fallbackFilename,
      title: title,
      mimeType: format == TranscriptExportFormat.docx
          ? _docxMimeType
          : 'text/markdown',
    );
  }

  static String _extension(TranscriptExportFormat format) =>
      format == TranscriptExportFormat.docx ? 'docx' : 'md';
}
