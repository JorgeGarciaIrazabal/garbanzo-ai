import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/admin/models/admin_model.dart';
import 'package:garbanzo_ai/features/admin/models/admin_user.dart';
import 'package:garbanzo_ai/features/admin/models/mcp_server.dart';

/// HTTP service for admin endpoints (users + MCP servers).
///
/// All calls require the current user to be an admin — non-admin tokens
/// receive a 403 and the service throws an [Exception].
class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  final ApiClient _api = ApiClient.instance;

  // ==========================================================================
  // Users
  // ==========================================================================

  Future<AdminUser> createUser({
    required String email,
    required String password,
    String? fullName,
    bool isAdmin = false,
  }) async {
    final body = <String, dynamic>{'email': email.trim(), 'password': password};
    if (fullName != null && fullName.trim().isNotEmpty) {
      body['full_name'] = fullName.trim();
    }
    if (isAdmin) body['is_admin'] = true;

    final res = await _api.post('/api/v1/admin/users', data: body);
    if (res.statusCode == 201 && res.data is Map<String, dynamic>) {
      return AdminUser.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  Future<List<AdminUser>> listUsers() async {
    final res = await _api.get('/api/v1/admin/users');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => AdminUser.fromJson(e))
          .toList();
    }
    throw _handleError(res);
  }

  Future<AdminUser> updateUser(
    String email, {
    bool? isAdmin,
    bool? isDisabled,
  }) async {
    final body = <String, dynamic>{};
    if (isAdmin != null) body['is_admin'] = isAdmin;
    if (isDisabled != null) body['is_disabled'] = isDisabled;
    final res = await _api.patch(
      '/api/v1/admin/users/${Uri.encodeComponent(email)}',
      data: body,
    );
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return AdminUser.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  // ==========================================================================
  // MCP servers
  // ==========================================================================

  Future<List<MCPServer>> listMCPServers() async {
    final res = await _api.get('/api/v1/admin/mcp-servers');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => MCPServer.fromJson(e))
          .toList();
    }
    throw _handleError(res);
  }

  Future<MCPServer> createMCPServer({
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

    final res = await _api.post('/api/v1/admin/mcp-servers', data: body);
    if ((res.statusCode == 200 || res.statusCode == 201) &&
        res.data is Map<String, dynamic>) {
      return MCPServer.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  Future<MCPServer> updateMCPServer(
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

    final res = await _api.patch('/api/v1/admin/mcp-servers/$id', data: body);
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return MCPServer.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  Future<void> deleteMCPServer(String id) async {
    final res = await _api.delete('/api/v1/admin/mcp-servers/$id');
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw _handleError(res);
    }
  }

  Future<MCPTestResult> testMCPServer(String id) async {
    final res = await _api.post(
      '/api/v1/admin/mcp-servers/$id/test-connection',
    );
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return MCPTestResult.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  // ==========================================================================
  // Models
  // ==========================================================================

  Future<List<AdminModel>> listModels() async {
    final res = await _api.get('/api/v1/admin/models');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => AdminModel.fromJson(e))
          .toList();
    }
    throw _handleError(res);
  }

  Future<List<AdminModel>> syncModels() async {
    final res = await _api.post('/api/v1/admin/models/sync');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => AdminModel.fromJson(e))
          .toList();
    }
    throw _handleError(res);
  }

  Future<AdminModel> updateModel(
    String modelId, {
    required bool enabled,
  }) async {
    final res = await _api.patch(
      '/api/v1/admin/models/${Uri.encodeComponent(modelId)}',
      data: {'is_enabled': enabled},
    );
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return AdminModel.fromJson(res.data as Map<String, dynamic>);
    }
    throw _handleError(res);
  }

  // ==========================================================================
  // Error handling
  // ==========================================================================

  Exception _handleError(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail']?.toString() ?? 'Unknown error';
      return Exception('API Error (${response.statusCode}): $detail');
    }
    return Exception('API Error (${response.statusCode}): $body');
  }
}
