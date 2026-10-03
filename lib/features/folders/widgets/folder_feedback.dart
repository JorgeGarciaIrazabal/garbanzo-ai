import 'package:flutter/material.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

void folderError(BuildContext context, Object error) {
  final l = AppLocalizations.of(context)!;
  final message = l.foldersError(error.toString());
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmFolderDelete(
  BuildContext context, {
  required bool folder,
}) async {
  final l = AppLocalizations.of(context)!;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.delete),
          content: Text(
            folder ? l.foldersDeleteConfirm : l.foldersFileDeleteConfirm,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.delete),
            ),
          ],
        ),
      ) ??
      false;
}
