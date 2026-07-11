import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:garbanzo_ai/core/auth_service.dart';

/// Navigation list to every feature page. One place to find everything,
/// instead of page links scattered between toggle sections.
class PagesSection extends StatelessWidget {
  const PagesSection({super.key});

  void _open(BuildContext context, String path) {
    Navigator.of(context).pop(); // close the drawer first
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService.instance.cachedUser?.isAdmin ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.psychology_outlined),
          title: const Text('Memories'),
          subtitle: const Text('What the assistant has learned about you'),
          dense: true,
          onTap: () => _open(context, '/memory'),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Knowledge base'),
          subtitle: const Text('Upload documents for retrieval across chats'),
          dense: true,
          onTap: () => _open(context, '/kb'),
        ),
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: const Text('Rooms'),
          subtitle: const Text('Multi-person, multi-agent chat rooms'),
          dense: true,
          onTap: () => _open(context, '/rooms'),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Skills library'),
          subtitle: const Text('Browse available MCP tools'),
          dense: true,
          onTap: () => _open(context, '/skills'),
        ),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Scheduled actions'),
          subtitle: const Text('Reminders and recurring prompts'),
          dense: true,
          onTap: () => _open(context, '/scheduled-actions'),
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: const Text('Token usage'),
          subtitle: const Text('Charts by model, conversation, day'),
          dense: true,
          onTap: () => _open(context, '/usage'),
        ),
        if (isAdmin)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Admin'),
            subtitle: const Text('Manage users and MCP servers'),
            dense: true,
            onTap: () => _open(context, '/admin'),
          ),
      ],
    );
  }
}
