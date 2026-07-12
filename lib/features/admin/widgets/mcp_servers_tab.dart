import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/admin/models/mcp_server.dart';
import 'package:garbanzo_ai/features/admin/providers/admin_provider.dart';
import 'package:garbanzo_ai/features/admin/widgets/mcp_server_dialog.dart';

/// Tab rendering the list of configured MCP servers.
class MCPServersTab extends StatefulWidget {
  const MCPServersTab({super.key});

  @override
  State<MCPServersTab> createState() => _MCPServersTabState();
}

class _MCPServersTabState extends State<MCPServersTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadServers();
    });
  }

  Future<void> _handleCreate() async {
    final result = await MCPServerDialog.show(context);
    if (result == null) return;
    if (!mounted) return;
    final provider = context.read<AdminProvider>();
    final created = await provider.createServer(
      name: result.name,
      description: result.description,
      url: result.url,
      transport: result.transport,
      command: result.command,
      args: result.args,
      env: result.env,
      authHeader: result.authHeader,
      enabled: result.enabled,
    );
    if (created == null && mounted && provider.serversError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.serversError!)));
    }
  }

  Future<void> _handleEdit(MCPServer server) async {
    final result = await MCPServerDialog.show(context, existing: server);
    if (result == null) return;
    if (!mounted) return;
    final provider = context.read<AdminProvider>();
    await provider.updateServer(
      server.id,
      name: result.name,
      description: result.description,
      url: result.url,
      transport: result.transport,
      command: result.command,
      args: result.args,
      env: result.env,
      authHeader: result.authHeader,
      enabled: result.enabled,
    );
  }

  Future<void> _handleDelete(MCPServer server) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete MCP server?'),
        content: Text(
          'Are you sure you want to delete "${server.name}"? This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<AdminProvider>().deleteServer(server.id);
  }

  Future<void> _handleTest(MCPServer server) async {
    final provider = context.read<AdminProvider>();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Testing ${server.name}…')));
    final result = await provider.testServer(server.id);
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.ok ? null : colorScheme.error,
        content: Text(
          result.ok
              ? 'OK: ${result.toolsCount} tools available'
              : 'Failed: ${result.error ?? "unknown error"}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget body;
    if (provider.isLoadingServers && provider.servers.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (provider.serversError != null && provider.servers.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(provider.serversError!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: provider.loadServers,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (provider.servers.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_off, color: colorScheme.outline, size: 48),
            const SizedBox(height: 8),
            Text(
              'No MCP servers configured',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Use the + button to add one.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: provider.loadServers,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: provider.servers.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final server = provider.servers[i];
            final summary = server.transport == McpTransport.stdio
                ? (server.command ?? '—')
                : (server.url ?? '—');

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: server.enabled
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.extension,
                  color: server.enabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              title: Row(
                children: [
                  Expanded(child: Text(server.name)),
                  _TransportBadge(transport: server.transport),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (server.description != null &&
                      server.description!.isNotEmpty)
                    Text(server.description!),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: server.enabled,
                    onChanged: (v) {
                      provider.updateServer(server.id, enabled: v);
                    },
                  ),
                  IconButton(
                    tooltip: 'Test connection',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => _handleTest(server),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _handleEdit(server),
                  ),
                  IconButton(
                    tooltip: 'Delete (long-press)',
                    icon: Icon(Icons.delete_outline, color: colorScheme.error),
                    onPressed: () => _handleDelete(server),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: _handleCreate,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.transport});
  final McpTransport transport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = mcpTransportToString(transport).toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
