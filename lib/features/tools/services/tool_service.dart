import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../models/mcp_tool.dart';

/// Service for fetching the set of MCP tools available to the current user.
class ToolService {
  ToolService._();
  static final ToolService instance = ToolService._();

  final ApiClient _api = ApiClient.instance;

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

  Exception _handleError(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail']?.toString() ?? 'Unknown error';
      return Exception('API Error (${response.statusCode}): $detail');
    }
    return Exception('API Error (${response.statusCode}): $body');
  }
}
