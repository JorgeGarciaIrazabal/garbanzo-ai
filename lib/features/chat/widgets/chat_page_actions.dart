import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/transcript_export_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/transcript_export_menu.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

void showChatSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      behavior: error ? SnackBarBehavior.floating : null,
    ),
  );
}

void deleteConversationWithUndoSnack(
  BuildContext context,
  ChatProvider chatProvider,
  String id,
) {
  chatProvider.deleteConversation(id);

  final media = MediaQuery.of(context);
  final horizontalMargin = ((media.size.width - 420) / 2).clamp(16.0, 400.0);
  final bottomMargin = (media.size.height - media.padding.top - 88).clamp(
    80.0,
    2000.0,
  );
  final l10n = AppLocalizations.of(context)!;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.messageConversationDeleted),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        margin: EdgeInsets.only(
          left: horizontalMargin,
          right: horizontalMargin,
          bottom: bottomMargin,
        ),
        action: SnackBarAction(
          label: l10n.labelUndo,
          onPressed: () => chatProvider.undoDeleteConversation(id),
        ),
      ),
    );
}

Future<void> downloadConversationTranscript(
  BuildContext context,
  TranscriptExportService service,
  Conversation conversation,
) => _downloadTranscript(
  context,
  load: (format) => service.downloadConversation(
    conversation.id,
    format: format,
    title: conversation.displayTitle,
  ),
);

Future<void> downloadRoomTranscript(
  BuildContext context,
  TranscriptExportService service,
  Room room,
) => _downloadTranscript(
  context,
  load: (format) =>
      service.downloadRoom(room.id, format: format, title: room.name),
);

Future<void> _downloadTranscript(
  BuildContext context, {
  required Future<void> Function(TranscriptExportFormat format) load,
}) async {
  final format = await showTranscriptFormatSheet(context);
  if (format == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  try {
    await load(format);
    if (context.mounted) {
      showChatSnack(context, l10n.messageTranscriptDownloaded);
    }
  } catch (e) {
    if (!context.mounted) return;
    final detail = e is ExportDownloadException ? e.detail : null;
    showChatSnack(
      context,
      detail == null
          ? l10n.messageTranscriptDownloadFailed
          : '${l10n.messageTranscriptDownloadFailed} ($detail)',
      error: true,
    );
  }
}
