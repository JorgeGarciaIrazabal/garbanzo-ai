import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/auth_state.dart';
import 'package:garbanzo_ai/features/notifications/providers/notification_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/app_settings_section.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/conversation_section.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/pages_section.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/section_header.dart';

/// Right-side drawer, organized into three groups:
///   1. Pages — navigation to every feature page
///   2. This conversation — model, prompt, context, tools for the open chat
///   3. App settings — appearance, chat display, voice, notifications
///
/// Section content lives in `drawer_sections/`; this file is just the shell.
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

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
            // Header — settings title + close
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
            // Account row — avatar, name/email, sign-out
            _AccountTile(),
            const Divider(height: 1),
            // Notifications row — bell with badge
            _NotificationsTile(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open full settings'),
              subtitle: const Text('Profile, appearance, models, and more'),
              dense: true,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings');
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

/// Compact account identity row with avatar, name/email, and sign-out action.
class _AccountTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = AuthService.instance.cachedUser;
    final displayName = (user?.fullName?.isNotEmpty ?? false)
        ? user!.fullName!
        : (user?.email ?? 'Unknown');
    final initials = _initials(displayName);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colorScheme.primary,
        child: Text(initials, style: TextStyle(color: colorScheme.onPrimary)),
      ),
      title: Text(
        displayName,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        user?.email ?? '',
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: IconButton(
        icon: Icon(Icons.logout, color: colorScheme.error),
        tooltip: 'Sign out',
        onPressed: () => context.read<AuthState>().logout(),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+|@'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    if (parts.length == 1) return first.toUpperCase();
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    return '$first$second'.toUpperCase();
  }
}

/// Notifications row with an unread badge that navigates to the notifications page.
class _NotificationsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final count = provider.unreadCount;

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (count > 0)
            Positioned(
              top: -4,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: const Text('Notifications'),
      trailing: const Icon(Icons.chevron_right),
      dense: true,
      onTap: () {
        Navigator.of(context).pop();
        context.push('/notifications');
      },
    );
  }
}
