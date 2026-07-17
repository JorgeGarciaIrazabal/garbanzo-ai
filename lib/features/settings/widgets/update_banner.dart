import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/router.dart';
import 'package:garbanzo_ai/features/settings/providers/update_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/update_dialog.dart';

/// Wraps the app with a slim top banner when a newer desktop build exists:
/// "v1.0.4 is available — Update / Later". Renders nothing off-desktop
/// (UpdateProvider never reports an update there).
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();
    if (!provider.showBanner) return child;
    final version = provider.result!.release.version;
    final theme = Theme.of(context);

    return Column(
      children: [
        Material(
          color: theme.colorScheme.primaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.system_update_alt,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Garbanzo AI v$version is available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('update_banner_later'),
                    onPressed: provider.snooze,
                    child: const Text('Later'),
                  ),
                  FilledButton(
                    key: const ValueKey('update_banner_update'),
                    onPressed: () {
                      provider.dismissBanner();
                      // The banner sits above the router's Navigator, so its
                      // own context can't open dialogs — the root navigator's
                      // context (below the app-level providers) can.
                      showUpdateDialog(
                        rootNavigatorKey.currentContext ?? context,
                      );
                    },
                    child: const Text('Update'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
