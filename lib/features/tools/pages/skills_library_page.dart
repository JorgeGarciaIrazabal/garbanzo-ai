import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/mcp_tool.dart';
import '../providers/tool_provider.dart';

/// Full-page view of every MCP tool available to the current user, grouped
/// by originating server.
class SkillsLibraryPage extends StatelessWidget {
  const SkillsLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ToolProvider()..load(),
      child: const _SkillsLibraryContent(),
    );
  }
}

class _SkillsLibraryContent extends StatefulWidget {
  const _SkillsLibraryContent();

  @override
  State<_SkillsLibraryContent> createState() => _SkillsLibraryContentState();
}

class _SkillsLibraryContentState extends State<_SkillsLibraryContent> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MCPTool> _filter(List<MCPTool> tools) {
    if (_query.isEmpty) return tools;
    final lower = _query.toLowerCase();
    return tools.where((t) {
      return t.name.toLowerCase().contains(lower) ||
          (t.description?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ToolProvider>();

    Widget body;
    if (provider.isLoading && provider.tools.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (provider.error != null && provider.tools.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child:
                  Text(provider.error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => provider.load(force: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else {
      final grouped = <String, List<MCPTool>>{};
      for (final t in _filter(provider.tools)) {
        grouped.putIfAbsent(t.serverName, () => []).add(t);
      }

      if (grouped.isEmpty) {
        body = Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _query.isEmpty
                  ? 'No tools available. Configure an MCP server first.'
                  : 'No tools match "${_query.trim()}".',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        );
      } else {
        body = ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: grouped.entries.map((entry) {
            return _ServerSection(
              serverName: entry.key,
              tools: entry.value,
            );
          }).toList(),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skills library'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tools…',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _query = '';
                            _searchController.clear();
                          });
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({required this.serverName, required this.tools});

  final String serverName;
  final List<MCPTool> tools;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.extension, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                serverName,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${tools.length} tool${tools.length == 1 ? "" : "s"})',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...tools.map((t) => _ToolTile(tool: t)),
        const Divider(),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});
  final MCPTool tool;

  void _showSchema(BuildContext context) {
    final encoder = const JsonEncoder.withIndent('  ');
    final prettyInput = tool.inputSchema == null
        ? 'No schema provided.'
        : encoder.convert(tool.inputSchema);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          minChildSize: 0.3,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${tool.serverName} / ${tool.name}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: prettyInput));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text('Schema copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      prettyInput,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        tool.name,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      subtitle: tool.description == null || tool.description!.isEmpty
          ? null
          : Text(tool.description!),
      trailing: TextButton.icon(
        icon: const Icon(Icons.code, size: 16),
        label: const Text('Show schema'),
        onPressed: () => _showSchema(context),
      ),
      dense: true,
      tileColor: theme.colorScheme.surface,
    );
  }
}
