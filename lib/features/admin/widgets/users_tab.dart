import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/admin/providers/admin_provider.dart';
import 'package:garbanzo_ai/features/admin/widgets/create_user_dialog.dart';

/// Tab rendering the list of registered users with admin/disabled toggles.
class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadUsers();
    });
  }

  Future<void> _handleCreateUser() async {
    final result = await CreateUserDialog.show(context);
    if (result == null) return;
    if (!mounted) return;
    final provider = context.read<AdminProvider>();
    final created = await provider.createUser(
      email: result.email,
      password: result.password,
      fullName: result.fullName,
      isAdmin: result.isAdmin,
    );
    if (!mounted) return;
    if (created == null && provider.usersError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.usersError!)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User ${result.email} created')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentEmail = AuthService.instance.cachedUser?.email;

    if (provider.isLoadingUsers && provider.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.usersError != null && provider.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                provider.usersError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: provider.loadUsers,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: provider.loadUsers,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: provider.users.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final user = provider.users[i];
            final isSelf = user.email == currentEmail;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: user.isDisabled
                    ? colorScheme.errorContainer
                    : colorScheme.primaryContainer,
                child: Icon(
                  user.isDisabled ? Icons.block : Icons.person,
                  color: user.isDisabled
                      ? colorScheme.onErrorContainer
                      : colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(user.email),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user.fullName != null && user.fullName!.isNotEmpty)
                    Text(user.fullName!),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (user.isAdmin)
                        Chip(
                          label: const Text('Admin'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.primaryContainer,
                          labelStyle: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 11,
                          ),
                        ),
                      if (user.isDisabled)
                        Chip(
                          label: const Text('Disabled'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.errorContainer,
                          labelStyle: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 11,
                          ),
                        ),
                      if (isSelf)
                        Chip(
                          label: const Text('You'),
                          visualDensity: VisualDensity.compact,
                          labelStyle: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LabeledSwitch(
                    label: 'Admin',
                    value: user.isAdmin,
                    disabled: isSelf,
                    onChanged: (v) {
                      provider.updateUser(user.email, isAdmin: v);
                    },
                  ),
                  const SizedBox(width: 8),
                  _LabeledSwitch(
                    label: 'Disabled',
                    value: user.isDisabled,
                    disabled: isSelf,
                    onChanged: (v) {
                      provider.updateUser(user.email, isDisabled: v);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('create_user_fab'),
        onPressed: _handleCreateUser,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

class _LabeledSwitch extends StatelessWidget {
  const _LabeledSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final String label;
  final bool value;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Switch(
          value: value,
          onChanged: disabled ? null : onChanged,
        ),
      ],
    );
  }
}
