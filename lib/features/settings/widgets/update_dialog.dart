import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:garbanzo_ai/features/settings/providers/update_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Changelog + "Download & install" dialog for an available update.
Future<void> showUpdateDialog(BuildContext context) {
  final provider = context.read<UpdateProvider>();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: provider,
      child: const UpdateDialog(),
    ),
  );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();
    final result = provider.result;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (result == null) return const SizedBox.shrink();
    final release = result.release;

    return AlertDialog(
      title: Text(l10n.updateToVersion(release.version)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.messageUpdateRestartAfterInstall(result.currentVersion),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (release.body != null && release.body!.trim().isNotEmpty)
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  // MarkdownBody (not Markdown): a scrollable inside
                  // AlertDialog breaks its intrinsic-width layout.
                  child: SingleChildScrollView(
                    child: MarkdownBody(data: release.body!),
                  ),
                ),
              ),
            if (provider.status == UpdateStatus.downloading ||
                provider.status == UpdateStatus.installing) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: provider.downloadProgress),
              const SizedBox(height: 8),
              Text(
                provider.status == UpdateStatus.installing
                    ? l10n.messageInstallAppRestart
                    : l10n.messageDownloadingUpdate,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (provider.status == UpdateStatus.error &&
                provider.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                provider.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: release.htmlUrl.isEmpty
              ? null
              : () => launchUrl(Uri.parse(release.htmlUrl)),
          child: Text(l10n.releasePage),
        ),
        TextButton(
          onPressed: provider.busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.labelClose),
        ),
        FilledButton(
          key: const ValueKey('update_install_button'),
          onPressed: provider.busy || result.asset == null
              ? null
              : provider.downloadAndInstall,
          child: Text(
            result.asset == null
                ? l10n.messageNoBuildForPlatform
                : l10n.downloadInstall,
          ),
        ),
      ],
    );
  }
}
