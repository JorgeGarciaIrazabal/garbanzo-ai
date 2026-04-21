import 'package:flutter/foundation.dart';

import '../models/admin_user.dart';
import '../models/mcp_server.dart';
import '../services/admin_service.dart';

/// ChangeNotifier managing admin state: users + MCP servers.
class AdminProvider extends ChangeNotifier {
  AdminProvider({AdminService? service})
      : _service = service ?? AdminService.instance;

  final AdminService _service;

  // ==========================================================================
  // Users state
  // ==========================================================================

  List<AdminUser> _users = [];
  List<AdminUser> get users => List.unmodifiable(_users);

  bool _isLoadingUsers = false;
  bool get isLoadingUsers => _isLoadingUsers;

  String? _usersError;
  String? get usersError => _usersError;

  // ==========================================================================
  // MCP servers state
  // ==========================================================================

  List<MCPServer> _servers = [];
  List<MCPServer> get servers => List.unmodifiable(_servers);

  bool _isLoadingServers = false;
  bool get isLoadingServers => _isLoadingServers;

  String? _serversError;
  String? get serversError => _serversError;

  // ==========================================================================
  // Users
  // ==========================================================================

  Future<void> loadUsers() async {
    _isLoadingUsers = true;
    _usersError = null;
    notifyListeners();
    try {
      _users = await _service.listUsers();
    } catch (e) {
      _usersError = 'Failed to load users: $e';
      if (kDebugMode) print(_usersError);
    } finally {
      _isLoadingUsers = false;
      notifyListeners();
    }
  }

  Future<void> updateUser(
    String email, {
    bool? isAdmin,
    bool? isDisabled,
  }) async {
    _usersError = null;
    try {
      final updated = await _service.updateUser(
        email,
        isAdmin: isAdmin,
        isDisabled: isDisabled,
      );
      final idx = _users.indexWhere((u) => u.email == email);
      if (idx >= 0) {
        _users = [
          ..._users.sublist(0, idx),
          updated,
          ..._users.sublist(idx + 1),
        ];
      } else {
        _users = [..._users, updated];
      }
      notifyListeners();
    } catch (e) {
      _usersError = 'Failed to update user: $e';
      if (kDebugMode) print(_usersError);
      notifyListeners();
    }
  }

  // ==========================================================================
  // MCP servers
  // ==========================================================================

  Future<void> loadServers() async {
    _isLoadingServers = true;
    _serversError = null;
    notifyListeners();
    try {
      _servers = await _service.listMCPServers();
    } catch (e) {
      _serversError = 'Failed to load servers: $e';
      if (kDebugMode) print(_serversError);
    } finally {
      _isLoadingServers = false;
      notifyListeners();
    }
  }

  Future<MCPServer?> createServer({
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
    _serversError = null;
    try {
      final created = await _service.createMCPServer(
        name: name,
        description: description,
        url: url,
        transport: transport,
        command: command,
        args: args,
        env: env,
        authHeader: authHeader,
        enabled: enabled,
      );
      _servers = [..._servers, created];
      notifyListeners();
      return created;
    } catch (e) {
      _serversError = 'Failed to create server: $e';
      if (kDebugMode) print(_serversError);
      notifyListeners();
      return null;
    }
  }

  Future<MCPServer?> updateServer(
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
    _serversError = null;
    try {
      final updated = await _service.updateMCPServer(
        id,
        name: name,
        description: description,
        url: url,
        transport: transport,
        command: command,
        args: args,
        env: env,
        authHeader: authHeader,
        enabled: enabled,
      );
      final idx = _servers.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        _servers = [
          ..._servers.sublist(0, idx),
          updated,
          ..._servers.sublist(idx + 1),
        ];
      } else {
        _servers = [..._servers, updated];
      }
      notifyListeners();
      return updated;
    } catch (e) {
      _serversError = 'Failed to update server: $e';
      if (kDebugMode) print(_serversError);
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteServer(String id) async {
    _serversError = null;
    try {
      await _service.deleteMCPServer(id);
      _servers.removeWhere((s) => s.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _serversError = 'Failed to delete server: $e';
      if (kDebugMode) print(_serversError);
      notifyListeners();
      return false;
    }
  }

  Future<MCPTestResult?> testServer(String id) async {
    try {
      return await _service.testMCPServer(id);
    } catch (e) {
      _serversError = 'Failed to test server: $e';
      if (kDebugMode) print(_serversError);
      notifyListeners();
      return MCPTestResult(ok: false, error: e.toString());
    }
  }

  void clearErrors() {
    _usersError = null;
    _serversError = null;
    notifyListeners();
  }
}
