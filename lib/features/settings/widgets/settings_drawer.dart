import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/app_settings_section.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/conversation_section.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/pages_section.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/section_header.dart';
import 'package:garbanzo_ai/features/settings/pages/settings_page.dart';

/// Right-side drawer, organized into three groups:
///   1. Pages — navigation to every feature page
///   2. This conversation — model, prompt, context, tools for the open chat
///   3. App settings — appearance, chat display, voice, notifications
///
/// Section content lives in `drawer_sections/`; this file is just the shell.
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key, this.onLogout});

  /// Forwarded to the dedicated settings page so its Profile section can
  /// sign out. Optional: callers that don't pass it get an in-place logout
  /// via AuthService but no navigation callback.
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;

    return Drawer(
      // Never wider than the screen (small phones / split screen).
      width: width < 400 ? width * 0.9 : 360,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.settings, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Settings', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close settings',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open full settings'),
              subtitle: const Text('Profile, appearance, models, and more'),
              dense: true,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(onLogout: onLogout ?? () {}),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GroupHeader(title: 'Pages'),
                    PagesSection(),
                    Divider(height: 24),
                    GroupHeader(title: 'This conversation'),
                    ConversationSection(),
                    Divider(height: 24),
                    GroupHeader(title: 'App settings'),
                    AppSettingsSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
