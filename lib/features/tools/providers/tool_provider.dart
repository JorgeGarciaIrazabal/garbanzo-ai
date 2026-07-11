import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/tools/models/mcp_tool.dart';
import 'package:garbanzo_ai/features/tools/services/tool_service.dart';

/// ChangeNotifier that fetches and caches the list of available MCP tools.
class ToolProvider extends ChangeNotifier with GuardedStateMixin {
  ToolProvider({ToolService? service})
      : _service = service ?? ToolService.instance;

  final ToolService _service;

  List<MCPTool> _tools = [];
  List<MCPTool> get tools => List.unmodifiable(_tools);

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Load the full tool catalog. Idempotent — calling repeatedly only triggers
  /// a single in-flight request.
  Future<void> load({bool force = false}) async {
    if (isLoading) return;
    if (_loaded && !force) return;
    await runGuarded('Failed to load tools', () async {
      _tools = await _service.listAllTools();
      _loaded = true;
    });
  }

  /// Group the current tools by server name, preserving tool order within each
  /// group and server order from the underlying list.
  Map<String, List<MCPTool>> get toolsByServer {
    final out = <String, List<MCPTool>>{};
    for (final t in _tools) {
      out.putIfAbsent(t.serverName, () => []).add(t);
    }
    return out;
  }
}
