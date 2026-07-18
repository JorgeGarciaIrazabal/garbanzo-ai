/// Supported MCP server transport types.
enum McpTransport { http, sse, stdio }

McpTransport mcpTransportFromString(String? v) {
  switch (v) {
    case 'http':
      return McpTransport.http;
    case 'sse':
      return McpTransport.sse;
    case 'stdio':
      return McpTransport.stdio;
    default:
      return McpTransport.http;
  }
}

String mcpTransportToString(McpTransport t) {
  switch (t) {
    case McpTransport.http:
      return 'http';
    case McpTransport.sse:
      return 'sse';
    case McpTransport.stdio:
      return 'stdio';
  }
}

/// An MCP server configuration as stored by the backend.
class MCPServer {
  final String id;
  final String name;
  final String? description;
  final String? url;
  final McpTransport transport;
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? authHeader;
  final bool enabled;

  /// Owner of a personal server; `null` for a global (admin-managed) one.
  final String? ownerEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MCPServer({
    required this.id,
    required this.name,
    this.description,
    this.url,
    this.transport = McpTransport.http,
    this.command,
    this.args,
    this.env,
    this.authHeader,
    this.enabled = true,
    this.ownerEmail,
    this.createdAt,
    this.updatedAt,
  });

  /// A global server has no owner; personal servers belong to one user.
  bool get isGlobal => ownerEmail == null;

  factory MCPServer.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['args'];
    List<String>? parsedArgs;
    if (rawArgs is List) {
      parsedArgs = rawArgs.map((e) => e.toString()).toList();
    }
    final rawEnv = json['env'];
    Map<String, String>? parsedEnv;
    if (rawEnv is Map) {
      parsedEnv = rawEnv.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return MCPServer(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
      url: json['url'] as String?,
      transport: mcpTransportFromString(json['transport'] as String?),
      command: json['command'] as String?,
      args: parsedArgs,
      env: parsedEnv,
      authHeader: json['auth_header'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      ownerEmail: json['owner_email'] as String?,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  MCPServer copyWith({
    String? id,
    String? name,
    String? description,
    String? url,
    McpTransport? transport,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? authHeader,
    bool? enabled,
    String? ownerEmail,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MCPServer(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      url: url ?? this.url,
      transport: transport ?? this.transport,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      authHeader: authHeader ?? this.authHeader,
      enabled: enabled ?? this.enabled,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Result of calling `/test-connection` on an MCP server.
class MCPTestResult {
  final bool ok;
  final int toolsCount;
  final String? error;

  const MCPTestResult({required this.ok, this.toolsCount = 0, this.error});

  factory MCPTestResult.fromJson(Map<String, dynamic> json) {
    return MCPTestResult(
      ok: json['ok'] as bool? ?? false,
      toolsCount: (json['tools_count'] as num?)?.toInt() ?? 0,
      error: json['error'] as String?,
    );
  }
}
