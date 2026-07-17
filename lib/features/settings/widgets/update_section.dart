import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/settings/providers/update_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/update_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// "Software update" settings section (desktop only): current vs latest
/// version, changelog access, and Check now / Download & install actions.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();
    final theme = Theme.of(context);
    final result = provider.result;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(AppLocalizations.of(context)!.titleCurrentVersion),
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
            title: Text(_statusLabel(provider)),
            subtitle: provider.status == UpdateStatus.error
                ? Text(
                    provider.errorMessage ?? 'Unknown error',
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                : (result?.hasUpdate ?? false)
                ? Text('Latest release: v${result!.release.version}')
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
                  child: Text(AppLocalizations.of(context)!.checkNow),
                ),
                if (result?.hasUpdate ?? false) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('update_open_dialog'),
                    onPressed: provider.busy
                        ? null
                        : () => showUpdateDialog(context),
                    child: Text(AppLocalizations.of(context)!.downloadInstall),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(UpdateProvider provider) {
    switch (provider.status) {
      case UpdateStatus.idle:
        return 'Updates are checked when the app starts';
      case UpdateStatus.checking:
        return 'Checking for updates…';
      case UpdateStatus.upToDate:
        return 'You are up to date';
      case UpdateStatus.available:
        return 'A newer version is available';
      case UpdateStatus.downloading:
        return 'Downloading update…';
      case UpdateStatus.installing:
        return 'Installing — the app will restart';
      case UpdateStatus.error:
        return 'Update check failed';
    }
  }
}
