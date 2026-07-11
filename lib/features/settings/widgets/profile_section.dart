import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/settings/widgets/change_password_dialog.dart';
import 'package:garbanzo_ai/features/settings/widgets/edit_profile_dialog.dart';

/// Profile block: shows account identity and exposes edit / password dialogs.
///
/// The settings page owns refresh; callers pass [onUserChanged] so the page
/// can re-read `AuthService.cachedUser` after a successful edit.
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.user,
    required this.onUserChanged,
    required this.onLogout,
  });

  final UserInfo? user;
  final VoidCallback onUserChanged;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = (user?.fullName?.isNotEmpty ?? false)
        ? user!.fullName!
        : (user?.email ?? 'Unknown user');

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary,
              child: Text(
                _initials(displayName),
                style: TextStyle(color: colorScheme.onPrimary),
              ),
            ),
            title: Text(
              displayName,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(user?.email ?? ''),
            trailing: user?.isAdmin ?? false
                ? Chip(
                    label: const Text('Admin'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: colorScheme.primaryContainer,
                    side: BorderSide.none,
                  )
                : null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit profile'),
            subtitle: const Text('Update name and email'),
            onTap: () async {
              final changed = await showDialog<bool>(
                context: context,
                builder: (_) => EditProfileDialog(user: user),
              );
              if (changed == true) onUserChanged();
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            onTap: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => const ChangePasswordDialog(),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: colorScheme.error),
            title: Text(
              'Sign out',
              style: TextStyle(color: colorScheme.error),
            ),
            onTap: () async {
              await AuthService.instance.logout();
              onLogout();
            },
          ),
        ],
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
