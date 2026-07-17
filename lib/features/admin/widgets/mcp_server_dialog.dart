import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/admin/models/mcp_server.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Result returned from [MCPServerDialog].
class MCPServerDialogResult {
  final String name;
  final String? description;
  final String? url;
  final McpTransport transport;
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? authHeader;
  final bool enabled;

  const MCPServerDialogResult({
    required this.name,
    this.description,
    this.url,
    required this.transport,
    this.command,
    this.args,
    this.env,
    this.authHeader,
    required this.enabled,
  });
}

/// Dialog for creating or editing an MCP server configuration.
class MCPServerDialog extends StatefulWidget {
  const MCPServerDialog({super.key, this.existing});

  final MCPServer? existing;

  static Future<MCPServerDialogResult?> show(
    BuildContext context, {
    MCPServer? existing,
  }) {
    return showAnimatedDialog<MCPServerDialogResult>(
      context: context,
      builder: (_) => MCPServerDialog(existing: existing),
    );
  }

  @override
  State<MCPServerDialog> createState() => _MCPServerDialogState();
}

class _MCPServerDialogState extends State<MCPServerDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _urlController;
  late final TextEditingController _commandController;
  late final TextEditingController _argsController;
  late final TextEditingController _envController;
  late final TextEditingController _authHeaderController;

  McpTransport _transport = McpTransport.http;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _urlController = TextEditingController(text: existing?.url ?? '');
    _commandController = TextEditingController(text: existing?.command ?? '');
    _argsController = TextEditingController(
      text: (existing?.args ?? const []).join('\n'),
    );
    _envController = TextEditingController(
      text: (existing?.env ?? const <String, String>{}).entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
    );
    _authHeaderController = TextEditingController(
      text: existing?.authHeader ?? '',
    );
    _transport = existing?.transport ?? McpTransport.http;
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _urlController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _envController.dispose();
    _authHeaderController.dispose();
    super.dispose();
  }

  List<String>? _parseArgs() {
    final text = _argsController.text.trim();
    if (text.isEmpty) return null;
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Map<String, String>? _parseEnv() {
    final text = _envController.text.trim();
    if (text.isEmpty) return null;
    final out = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      out[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
    }
    return out.isEmpty ? null : out;
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final isStdio = _transport == McpTransport.stdio;
    final result = MCPServerDialogResult(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      url: isStdio || _urlController.text.trim().isEmpty
          ? null
          : _urlController.text.trim(),
      transport: _transport,
      command: !isStdio || _commandController.text.trim().isEmpty
          ? null
          : _commandController.text.trim(),
      args: isStdio ? _parseArgs() : null,
      env: isStdio ? _parseEnv() : null,
      authHeader: _authHeaderController.text.trim().isEmpty
          ? null
          : _authHeaderController.text.trim(),
      enabled: _enabled,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isStdio = _transport == McpTransport.stdio;

    return AlertDialog(
      title: Text(isEdit ? 'Edit MCP server' : 'New MCP server'),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelName,
                  hintText: AppLocalizations.of(context)!.hintEGFilesystem,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelDescription,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(AppLocalizations.of(context)!.transport),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<McpTransport>(
                      segments: [
                        ButtonSegment(
                          value: McpTransport.http,
                          label: Text(AppLocalizations.of(context)!.labelHttp),
                        ),
                        ButtonSegment(
                          value: McpTransport.sse,
                          label: Text(AppLocalizations.of(context)!.labelSse),
                        ),
                        ButtonSegment(
                          value: McpTransport.stdio,
                          label: Text(AppLocalizations.of(context)!.labelStdio),
                        ),
                      ],
                      selected: {_transport},
                      onSelectionChanged: (sel) {
                        setState(() => _transport = sel.first);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!isStdio)
                TextFormField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.labelUrl,
                    hintText: 'https://example.com/mcp',
                  ),
                  validator: (v) {
                    if (isStdio) return null;
                    if (v == null || v.trim().isEmpty) {
                      return 'URL is required for HTTP/SSE transports';
                    }
                    return null;
                  },
                ),
              if (isStdio) ...[
                TextFormField(
                  controller: _commandController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.labelCommand,
                    hintText: AppLocalizations.of(context)!.hintUsrBinPython3,
                  ),
                  validator: (v) {
                    if (!isStdio) return null;
                    if (v == null || v.trim().isEmpty) {
                      return 'Command is required for stdio transport';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _argsController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.labelArgsOnePerLine,
                    hintText: '-m\nmcp_server',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _envController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.labelEnvKeyValueOnePerLine,
                    hintText: 'API_KEY=abc\nDEBUG=1',
                  ),
                  maxLines: 4,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _authHeaderController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelAuthHeader,
                  hintText: AppLocalizations.of(context)!.hintBearer,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: Text(AppLocalizations.of(context)!.labelEnabled),
                subtitle: Text(
                  AppLocalizations.of(context)!.messageDisabledServersIgnored,
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
