import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/tools/models/mcp_tool.dart';

/// Service for fetching the set of MCP tools available to the current user.
class ToolService {
  ToolService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final ToolService instance = ToolService();

  final ApiClient _api;

  Future<List<MCPTool>> listAllTools() async {
    final res = await _api.get('/api/v1/mcp/tools');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => MCPTool.fromJson(e))
          .toList();
    }
    throw _handleError(res);
  }

  Exception _handleError(Response<dynamic> response) =>
      apiResponseError(response, operation: 'Failed to load tools');
}
