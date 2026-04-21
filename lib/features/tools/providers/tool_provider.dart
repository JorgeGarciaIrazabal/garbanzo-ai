import 'package:flutter/foundation.dart';

import '../models/mcp_tool.dart';
import '../services/tool_service.dart';

/// ChangeNotifier that fetches and caches the list of available MCP tools.
class ToolProvider extends ChangeNotifier {
  ToolProvider({ToolService? service})
      : _service = service ?? ToolService.instance;

  final ToolService _service;

  List<MCPTool> _tools = [];
  List<MCPTool> get tools => List.unmodifiable(_tools);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Load the full tool catalog. Idempotent — calling repeatedly only triggers
  /// a single in-flight request.
  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (_loaded && !force) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _tools = await _service.listAllTools();
      _loaded = true;
    } catch (e) {
      _error = 'Failed to load tools: $e';
      if (kDebugMode) print(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
