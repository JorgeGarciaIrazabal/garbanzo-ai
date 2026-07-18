import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/admin/models/mcp_server.dart';

/// HTTP service for a user's *personal* MCP servers (`/api/v1/mcp/servers`).
///
/// Mirrors [AdminService]'s MCP methods but scoped to the current user: the
/// backend stamps each server with the caller's email and only ever returns,
/// updates, or deletes servers that user owns. Global (admin-managed) servers
/// are not reachable here.
class UserMcpService {
  UserMcpService._();
  static final UserMcpService instance = UserMcpService._();

  final ApiClient _api = ApiClient.instance;

  Future<List<MCPServer>> listServers() async {
    final res = await _api.get('/api/v1/mcp/servers');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => MCPServer.fromJson(e))
          .toList();
    }
    throw _handleError(res);
  }

  Future<MCPServer> createServer({
    required String name,
    String? description,
    String? url,
    required McpTransport transport,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? authHeader,
    bool enabled = true,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'transport': mcpTransportToString(transport),
      'enabled': enabled,
    };
    if (description != null && description.isNotEmpty) {
      body['description'] = description;
    }
    if (url != null && url.isNotEmpty) body['url'] = url;
    if (command != null && command.isNotEmpty) body['command'] = command;
    if (args != null) body['args'] = args;
    if (env != null) body['env'] = env;
    if (authHeader != null && authHeader.isNotEmpty) {
      body['auth_header'] = authHeader;
    }

    final res = await _api.post('/api/v1/mcp/servers', data: body);
    if ((res.statusCode == 200 || res.statusCode == 201) &&
        res.data is Map<String, dynamic>) {
      return MCPServer.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  Future<MCPServer> updateServer(
    String id, {
    String? name,
    String? description,
    String? url,
    McpTransport? transport,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? authHeader,
    bool? enabled,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (url != null) body['url'] = url;
    if (transport != null) body['transport'] = mcpTransportToString(transport);
    if (command != null) body['command'] = command;
    if (args != null) body['args'] = args;
    if (env != null) body['env'] = env;
    if (authHeader != null) body['auth_header'] = authHeader;
    if (enabled != null) body['enabled'] = enabled;

    final res = await _api.patch('/api/v1/mcp/servers/$id', data: body);
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return MCPServer.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  Future<void> deleteServer(String id) async {
    final res = await _api.delete('/api/v1/mcp/servers/$id');
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw _handleError(res);
    }
  }

  Future<MCPTestResult> testServer(String id) async {
    final res = await _api.post('/api/v1/mcp/servers/$id/test-connection');
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return MCPTestResult.fromJson(res.data as Map<String, dynamic>);
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
