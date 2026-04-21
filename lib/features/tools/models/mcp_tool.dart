/// A single MCP tool exposed by a server.
class MCPTool {
  final String serverId;
  final String serverName;
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  const MCPTool({
    required this.serverId,
    required this.serverName,
    required this.name,
    this.description,
    this.inputSchema,
  });

  factory MCPTool.fromJson(Map<String, dynamic> json) {
    final rawSchema = json['input_schema'];
    Map<String, dynamic>? schema;
    if (rawSchema is Map<String, dynamic>) {
      schema = rawSchema;
    } else if (rawSchema is Map) {
      schema = rawSchema.map((k, v) => MapEntry(k.toString(), v));
    }
    return MCPTool(
      serverId: (json['server_id'] as String?) ?? '',
      serverName: (json['server_name'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
      inputSchema: schema,
    );
  }

  /// A stable identifier used for the conversation's `enabled_tools` list.
  /// Matches the backend `tool_key` helper: `<server_id>:<tool_name>`.
  String get qualifiedKey => '$serverId:$name';
}
