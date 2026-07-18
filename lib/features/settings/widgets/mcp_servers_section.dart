import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/admin/models/mcp_server.dart';
import 'package:garbanzo_ai/features/admin/widgets/mcp_server_dialog.dart';
import 'package:garbanzo_ai/features/settings/services/user_mcp_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Settings section listing the user's *personal* MCP tool servers.
///
/// Self-contained (like [LocationSection]): it owns its state and talks to
/// [UserMcpService] directly rather than through a provider. Reuses the admin
/// [MCPServerDialog] form for create/edit.
class McpServersSection extends StatefulWidget {
  const McpServersSection({super.key});

  @override
  State<McpServersSection> createState() => _McpServersSectionState();
}

class _McpServersSectionState extends State<McpServersSection> {
  final UserMcpService _service = UserMcpService.instance;

  List<MCPServer> _servers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await _service.listServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? colorScheme.error : null,
      ),
    );
  }

  Future<void> _handleCreate() async {
    final result = await MCPServerDialog.show(context);
    if (result == null || !mounted) return;
    try {
      final created = await _service.createServer(
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
      setState(() => _servers = [..._servers, created]);
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _handleEdit(MCPServer server) async {
    final result = await MCPServerDialog.show(context, existing: server);
    if (result == null || !mounted) return;
    try {
      final updated = await _service.updateServer(
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
      _replace(updated);
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _toggleEnabled(MCPServer server, bool value) async {
    try {
      final updated = await _service.updateServer(server.id, enabled: value);
      _replace(updated);
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  void _replace(MCPServer updated) {
    if (!mounted) return;
    final idx = _servers.indexWhere((s) => s.id == updated.id);
    setState(() {
      if (idx >= 0) {
        _servers = [
          ..._servers.sublist(0, idx),
          updated,
          ..._servers.sublist(idx + 1),
        ];
      } else {
        _servers = [..._servers, updated];
      }
    });
  }

  Future<void> _handleDelete(MCPServer server) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.titleDeleteMcpServer),
        content: Text(
          'Are you sure you want to delete "${server.name}"? This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteServer(server.id);
      setState(
        () => _servers = _servers.where((s) => s.id != server.id).toList(),
      );
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _handleTest(MCPServer server) async {
    _snack('Testing ${server.name}…');
    try {
      final result = await _service.testServer(server.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _snack(
        result.ok
            ? 'OK: ${result.toolsCount} tools available'
            : 'Failed: ${result.error ?? "unknown error"}',
        error: !result.ok,
      );
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.titleMyMcpServers,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _handleCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.labelAddServer),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.messagePersonalMcpServersHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _buildBody(context, theme, colorScheme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _servers.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 8),
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton(onPressed: _load, child: Text(l10n.labelRetry)),
        ],
      );
    }
    if (_servers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          l10n.messageNoMcpServersConfigured,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final server in _servers)
          _serverTile(server, theme, colorScheme, l10n),
      ],
    );
  }

  Widget _serverTile(
    MCPServer server,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final summary = server.transport == McpTransport.stdio
        ? (server.command ?? '—')
        : (server.url ?? '—');
    return ListTile(
      contentPadding: EdgeInsets.zero,
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
      title: Text(server.name),
      subtitle: Text(
        summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: server.enabled,
            onChanged: (v) => _toggleEnabled(server, v),
          ),
          IconButton(
            tooltip: l10n.tooltipTestConnection,
            icon: const Icon(Icons.play_arrow),
            onPressed: () => _handleTest(server),
          ),
          IconButton(
            tooltip: l10n.tooltipEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _handleEdit(server),
          ),
          IconButton(
            tooltip: l10n.tooltipDeleteLongPress,
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            onPressed: () => _handleDelete(server),
          ),
        ],
      ),
    );
  }
}
