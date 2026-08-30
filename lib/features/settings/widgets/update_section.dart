import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/platform_info.dart';
import 'package:garbanzo_ai/features/settings/providers/update_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/update_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// "Software update" settings section: current vs latest
/// version, changelog access, and Check now / Download & install actions.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final result = provider.result;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.titleCurrentVersion),
            subtitle: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) =>
                  Text(snapshot.data?.version ?? '…'),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(switch (provider.status) {
              UpdateStatus.available ||
              UpdateStatus.downloading ||
              UpdateStatus.installing => Icons.system_update_alt,
              UpdateStatus.upToDate => Icons.check_circle_outline,
              UpdateStatus.error => Icons.error_outline,
              _ => Icons.update,
            }),
            title: Text(_statusLabel(l10n, provider)),
            subtitle: provider.status == UpdateStatus.error
                ? Text(
                    _errorLabel(l10n, provider),
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                : (result?.hasUpdate ?? false)
                ? Text(l10n.latestReleaseVersion(result!.release.version))
                : null,
            trailing: provider.status == UpdateStatus.checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const ValueKey('update_check_now'),
                  onPressed:
                      provider.busy || provider.status == UpdateStatus.checking
                      ? null
                      : provider.checkNow,
                  child: Text(l10n.checkNow),
                ),
                if (result?.hasUpdate ?? false) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('update_open_dialog'),
                    onPressed: provider.busy
                        ? null
                        : () => showUpdateDialog(context),
                    child: Text(l10n.downloadInstall),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n, UpdateProvider provider) {
    switch (provider.status) {
      case UpdateStatus.idle:
        return l10n.messageUpdatesCheckedAtStart;
      case UpdateStatus.checking:
        return l10n.messageCheckingForUpdates;
      case UpdateStatus.upToDate:
        return l10n.messageUpToDate;
      case UpdateStatus.available:
        return l10n.messageNewerVersionAvailable;
      case UpdateStatus.downloading:
        return l10n.messageDownloadingUpdate;
      case UpdateStatus.installing:
        return PlatformInfo.isAndroid
            ? l10n.messageInstallAndroidConfirm
            : l10n.messageInstallAppRestart;
      case UpdateStatus.error:
        return provider.errorKind == UpdateErrorKind.check
            ? l10n.messageUpdateCheckFailed
            : l10n.messageInstallFailed;
    }
  }

  String _errorLabel(AppLocalizations l10n, UpdateProvider provider) {
    if (provider.errorKind == UpdateErrorKind.installPermission) {
      return l10n.messageAllowInstallPermission;
    }
    return provider.errorMessage ?? l10n.messageUnknownError;
  }
}
