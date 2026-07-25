# MCP / Admin API Contract

All endpoints are prefixed with `/api/v1/` and require a Bearer JWT in
`Authorization: Bearer <token>` unless noted. Admin routes additionally
require the user to have `is_admin=true`.

## Admin — Users

### `GET /admin/users`
Response: `AdminUserOut[]`
```json
{ "email": "a@b.com", "full_name": "Alice",
  "created_at": "2026-04-20T12:00:00Z",
  "is_admin": true, "is_disabled": false }
```

### `PATCH /admin/users/{email}`
Request (all fields optional):
```json
{ "is_admin": true, "is_disabled": false }
```
Response: `AdminUserOut`. 400 if an admin tries to revoke their own admin
status or disable themselves.

## Admin — MCP Servers

### `GET /admin/mcp-servers`
Response: `MCPServerOut[]`.

### `POST /admin/mcp-servers`
Request — either HTTP/SSE or stdio transport:
```json
// HTTP/SSE
{ "name": "weather", "transport": "sse",
  "url": "https://mcp.example.com/sse",
  "auth_header": "Bearer xyz",
  "description": "…", "enabled": true }

// stdio
{ "name": "filesystem", "transport": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
  "env": { "FOO": "bar" },
  "enabled": true }
```
Response (201): `MCPServerOut`
```json
{ "id": "uuid", "name": "…", "description": "…",
  "transport": "http|sse|stdio",
  "url": "…", "auth_header": "…",
  "command": "…", "args": [], "env": {},
  "enabled": true, "created_by": "admin@...",
  "created_at": "…", "updated_at": "…" }
```

### `PATCH /admin/mcp-servers/{id}`
Only fields present in the body are updated. Any field shaped like the
create request is acceptable. Response: `MCPServerOut`. 404 if unknown.

### `DELETE /admin/mcp-servers/{id}`
Response: 204. 404 if unknown.

### `POST /admin/mcp-servers/{id}/test-connection`
Opens a short-lived MCP session and lists tools.
Response: `MCPServerTestResult`
```json
{ "ok": true, "tools_count": 3, "error": null }
```
or, on failure:
```json
{ "ok": false, "tools_count": 0, "error": "connect refused" }
```

## User — Tools

### `GET /mcp/tools`
Auth required (any user). Returns the union of tools from all **enabled**
MCP servers. Results are cached server-side for ~60 seconds.
```json
[
  { "server_id": "uuid", "server_name": "filesystem",
    "name": "list_files",
    "description": "…",
    "input_schema": { "type": "object", "properties": { ... } } }
]
```
Tool selection keys for `enabled_tools` use `"{server_id}:{tool_name}"`.

## Conversation — Tool Selection

`PATCH /chat/conversations/{id}` accepts an optional `enabled_tools`:

| Request value                   | Effect                                   |
| ------------------------------- | ---------------------------------------- |
| key omitted                     | Leave unchanged                          |
| `"enabled_tools": null`         | Clear — conversation gets **all** enabled tools |
| `"enabled_tools": []`           | Disable tools entirely for this chat     |
| `"enabled_tools": ["srv:foo"]`  | Whitelist only the listed tools          |

`ConversationOut`/`ConversationDetailOut` include the column in the
response:
```json
{ "id": "…", "enabled_tools": ["uuid:list_files"] }
```

## Chat SSE Chunks

The SSE stream at `POST /chat/conversations/{id}/chat` adds two new chunk
types. Each event is `data: <json>\n\n`.

| `type`         | Fields                                          |
| -------------- | ----------------------------------------------- |
| `chunk`        | `content` (string)                              |
| `thinking`     | `content` (string)                              |
| `tool_call`    | `tool_calls` (array of `{id, name, arguments}`) |
| `tool_result`  | `tool_result` (`{tool_call_id, tool_name, result}`) |
| `done`         | `metadata` (`{tokens_generated, ..., has_tool_calls?}`) |
| `error`        | `error` (string), `metadata`                    |

`tool_call.name` is the Ollama-shaped function name, which equals
`"{server_id}:{tool_name}"`. The backend executes the tools via MCP before
the next `chunk`/`done` pair.

If a conversation keeps requesting tools beyond 5 iterations, the engine runs
one final tools-stripped pass so the model answers from the results it has. If
that capped pass still produces no assistant content (e.g. the model spent
every iteration on `web_search` and then stopped), the engine synthesizes a
fallback assistant message naming the tools that ran, so the user is never
left with a silent turn after tool activity. That message's finish chunk is
flagged with
`{"tool_iteration_cap": true, "max_iterations": 5}` (no `error_type`). The
terminal `{"error_type": "tool_iteration_cap"}` chunk fires only when the
loop exits without that clean synthesized finish.

## Message Roles

`Message.role` now includes, in addition to `user`/`assistant`/`system`:

* `tool_call` — stored once per iteration; `content` is a JSON array of
  `{id, name, arguments}`, also mirrored in `meta.tool_calls`.
* `tool_result` — one per invoked tool; `content` is a JSON-serialised
  result; `meta` is `{tool_call_id, tool_name, result}`.

## Disabled Users

A user flagged `is_disabled=true` is rejected at `POST /auth/login` with
403 "Account disabled". Already-issued JWTs remain valid until they expire
— disabling does not revoke active sessions.

## Config

Environment variables (backend `.env`):

```
ADMIN_EMAILS=alice@example.com,bob@example.com
```
Matching users are auto-promoted to `is_admin=true` on backend startup.
Unknown emails are ignored.
