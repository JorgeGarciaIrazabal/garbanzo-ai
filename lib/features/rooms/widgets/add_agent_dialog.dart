import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';

/// Show the "Add agent" dialog. Returns when the dialog closes.
Future<void> showAddAgentDialog(BuildContext context, RoomProvider provider) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _AddAgentDialog(provider: provider),
  );
}

class _AddAgentDialog extends StatefulWidget {
  const _AddAgentDialog({required this.provider});
  final RoomProvider provider;

  @override
  State<_AddAgentDialog> createState() => _AddAgentDialogState();
}

class _AddAgentDialogState extends State<_AddAgentDialog> {
  final _nameCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  String _mode = 'mention';
  bool _moderator = false;
  bool _saving = false;
  bool _allTools = true;
  Set<String> _selectedTools = {};

  List<ModelInfo>? _models; // null = loading
  String? _modelLoadError;
  String? _selectedModelId;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final list = await ChatService.instance.listModels();
      if (!mounted) return;
      setState(() {
        _models = list.models;
        _selectedModelId = _pickDefault(list.models);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelLoadError = e.toString();
        _models = const [];
      });
    }
  }

  String? _pickDefault(List<ModelInfo> models) {
    if (models.isEmpty) return null;
    final llama = models
        .where((m) => m.id.contains('llama3.2'))
        .cast<ModelInfo?>();
    return (llama.isNotEmpty ? llama.first : models.first)?.id;
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final modelId = _selectedModelId;
    if (name.isEmpty || modelId == null || modelId.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.provider.addAgent(
        name: name,
        model: modelId,
        systemPrompt: _promptCtrl.text.trim().isEmpty
            ? null
            : _promptCtrl.text.trim(),
        responseMode: _mode,
        isModerator: _moderator,
        enabledTools: _allTools ? null : _selectedTools.toList(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add agent'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Agent name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _buildModelSelector(),
              const SizedBox(height: 12),
              TextField(
                controller: _promptCtrl,
                decoration: const InputDecoration(
                  labelText: 'System prompt (optional)',
                  hintText: 'You are a friendly product strategist…',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: 'When to respond'),
                items: const [
                  DropdownMenuItem(
                    value: 'mention',
                    child: Text('On @mention only'),
                  ),
                  DropdownMenuItem(
                    value: 'always',
                    child: Text('Always respond'),
                  ),
                  DropdownMenuItem(
                    value: 'round_robin',
                    child: Text('Round-robin (take turns)'),
                  ),
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text('Auto — jump in when relevant (LLM)'),
                  ),
                ],
                onChanged: (v) => setState(() => _mode = v ?? 'mention'),
              ),
              const SizedBox(height: 8),
              _buildToolSelector(),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Moderator'),
                subtitle: const Text(
                  'Helps summarize, break ties, keep things on track',
                ),
                value: _moderator,
                onChanged: (v) => setState(() => _moderator = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _saving ||
                  _selectedModelId == null ||
                  _nameCtrl.text.trim().isEmpty
              ? null
              : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildModelSelector() {
    final theme = Theme.of(context);
    if (_models == null) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Model'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading models…'),
            ],
          ),
        ),
      );
    }

    if (_models!.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Model',
          errorText: _modelLoadError != null
              ? 'Could not load models'
              : 'No models available',
        ),
        child: TextButton.icon(
          onPressed: () {
            setState(() {
              _models = null;
              _modelLoadError = null;
            });
            _loadModels();
          },
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry'),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedModelId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Model',
        prefixIcon: Icon(Icons.memory, size: 18),
      ),
      items: _models!.map((m) {
        return DropdownMenuItem<String>(
          value: m.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                m.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (m.description != null && m.description!.isNotEmpty)
                Text(
                  m.description!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        );
      }).toList(),
      selectedItemBuilder: (_) => _models!
          .map(
            (m) => Align(
              alignment: Alignment.centerLeft,
              child: Text(m.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedModelId = v),
    );
  }

  Widget _buildToolSelector() {
    return Consumer<ToolProvider>(
      builder: (context, toolProvider, _) {
        if (!toolProvider.isLoaded && !toolProvider.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            toolProvider.load();
          });
        }
        final tools = toolProvider.tools;
        final allKeys = tools.map((t) => t.qualifiedKey).toSet();

        return ExpansionTile(
          leading: const Icon(Icons.build_outlined, size: 18),
          title: const Text('Tools'),
          subtitle: Text(
            _allTools
                ? 'All tools enabled'
                : '${_selectedTools.length} of ${allKeys.length} tools enabled',
          ),
          dense: true,
          childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            if (toolProvider.isLoading && tools.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Loading tools…'),
                  ],
                ),
              )
            else if (tools.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Text(
                  'No MCP tools available. Configure from the Admin panel.',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else ...[
              SwitchListTile(
                title: const Text('All tools'),
                value: _allTools,
                onChanged: (v) => setState(() {
                  _allTools = v;
                  if (!v) _selectedTools = Set.from(allKeys);
                }),
                dense: true,
              ),
              if (!_allTools)
                ...toolProvider.toolsByServer.entries.map((entry) {
                  final serverTools = entry.value;
                  return Column(
                    children: serverTools.map((tool) {
                      final key = tool.qualifiedKey;
                      final isOn = _selectedTools.contains(key);
                      return CheckboxListTile(
                        value: isOn,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedTools.add(key);
                          } else {
                            _selectedTools.remove(key);
                          }
                        }),
                        title: Text(
                          tool.name,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }).toList(),
                  );
                }),
            ],
          ],
        );
      },
    );
  }
}
