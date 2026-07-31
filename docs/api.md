# API Endpoint Reference

All endpoints are prefixed with `/api/v1/`. Auth uses the `get_current_user`
dependency validating `Authorization: Bearer <token>`. Keep this table current:
when you add or change an endpoint, update the matching row in the same commit.

| Group | Endpoints |
|-------|-----------|
| **Auth** | `POST /auth/login`, `POST /auth/register` (disabled, 403), `POST /auth/refresh`, `GET /auth/me`, `PATCH /auth/me` (profile incl. `timezone`/`locale`/`location`), `POST /auth/me/location` (coords → reverse-geocoded city, coords never stored), `POST /auth/me/password`, `POST /auth/me/avatar`, `DELETE /auth/me/avatar` |
| **Admin** | `POST /admin/users`, `GET /admin/users`, `PATCH /admin/users/{email}`, `GET /admin/mcp-servers`, `POST /admin/mcp-servers`, `PATCH /admin/mcp-servers/{id}`, `DELETE /admin/mcp-servers/{id}`, `POST /admin/mcp-servers/{id}/test-connection`, `GET /admin/models`, `POST /admin/models/sync`, `PATCH /admin/models` |
| **Chat** | `GET/POST /chat/conversations`, `GET /chat/conversations/search`, `GET /chat/conversations/{id}` (optional `message_limit` — most-recent-N window instead of full history, B-03), `GET /chat/conversations/{id}/messages?before=&limit=` (page in older messages), `PATCH /chat/conversations/{id}`, `PATCH /chat/conversations/{id}/mute`, `POST /chat/conversations/{id}/client-tool-result` (desktop client returns an on-demand folder read — idea 17; body `{tool_call_id, ok, filename?, data?(base64), entries?, error?}`), `DELETE /chat/conversations/{id}`, `POST /chat/conversations/{id}/chat` (SSE stream whose detached producer finishes if the client disconnects; `has_client_folder` advertises client-served read tools; optional `talk_mode_instruction` adds localized ephemeral system context for that turn), `POST /chat/conversations/{id}/messages/{mid}/regenerate` (detached SSE), `POST /chat/conversations/{id}/messages/{mid}/edit` (detached SSE), `POST /chat/conversations/{id}/messages/{mid}/branch`, `DELETE /chat/conversations/{id}/chat` (cancel stream), `GET /chat/models`, `GET /chat/health/llm` |
| **System Prompts** | `GET /system-prompts/templates` (optional `?locale=` query — filters builtins to the requested language when one is seeded for it; user-saved templates always surface), `POST /system-prompts/templates`, `PATCH /system-prompts/templates/{id}`, `DELETE /system-prompts/templates/{id}`, `GET /system-prompts/user-default`, `PUT /system-prompts/user-default`, `POST /system-prompts/generate` (SSE stream) |
| **STT** | `POST /stt/transcribe` (optional `language` form field — ISO code or `"auto"`/omitted for per-clip detection, idea 13), `GET /stt/health` |
| **TTS** | `POST /tts/speak`, `POST /tts/speak/stream` (text is limited to 5,000 characters per request; both take optional `language` — ISO code; swaps in that language's default voice when `voice` doesn't speak it, idea 13), `GET /tts/voices` (each voice carries `language` + ISO `lang_code`; en/es/fr/hi/it/pt), `GET /tts/health` |
| **Memories** | `POST /memories`, `GET /memories`, `GET /memories/{id}`, `PATCH /memories/{id}`, `DELETE /memories/{id}` |
| **Knowledge Base** | `POST /kb/documents`, `GET /kb/documents`, `GET /kb/documents/{id}`, `DELETE /kb/documents/{id}`, `GET /kb/search` |
| **Rooms** | `POST /rooms`, `GET /rooms`, `GET /rooms/search`, `GET /rooms/{id}`, `PATCH /rooms/{id}`, `DELETE /rooms/{id}`, `GET /rooms/{id}/members`, `POST /rooms/{id}/members`, `DELETE /rooms/{id}/members/{email}`, `PATCH /rooms/{id}/members/me/mute`, `GET /rooms/{id}/agents`, `POST /rooms/{id}/agents`, `PATCH /rooms/{id}/agents/{id}`, `DELETE /rooms/{id}/agents/{id}`, `GET /rooms/{id}/messages`, `POST /rooms/{id}/chat`, `POST /rooms/{id}/audio-notes` (multipart 16 kHz mono WAV, ≤2 min; transcribes, persists, and starts detached agent turns), `GET /rooms/{id}/audio-notes/{note_id}` (member-only raw playback), `GET /rooms/{id}/export`, `WS /rooms/{id}` |
| **Micro-apps** | `POST /microapps/workspace`, `GET /microapps/workspace`, `DELETE /microapps/workspace`, `GET /microapps/apps`, `GET /microapps/houses`, `POST /microapps/houses`, `POST /microapps/agent/chat`, `POST /microapps/agent/abort`, `GET /microapps/changes`, `POST /microapps/publish`, `POST /microapps/revert` |
| **Workflows** | `POST /workflows` (create a delegated opencode run in `draft`; body `{instruction, mode:"folder"|"research", conversation_id?, room_id?, tool_call_id?, folder_label?}`), `GET /workflows?conversation_id=` (hydrate proposal cards after reload), `POST /workflows/{id}/files` (folder mode only: upload a snapshot batch), `POST /workflows/{id}/start` (git-baseline the folder snapshot or empty research workdir and launch the **detached** run), `GET /workflows/{id}?since=` (status + progress after the cursor), `GET /workflows/{id}/changes` and `POST /workflows/{id}/applied` (folder mode diff/cleanup), `GET /workflows/{id}/output` (completed research mode: markdown summary attachment) |
| **MCP (Tools)** | `GET /mcp/tools`, `GET /mcp/servers`, `POST /mcp/servers`, `PATCH /mcp/servers/{id}`, `DELETE /mcp/servers/{id}`, `POST /mcp/servers/{id}/test-connection` |
| **Notifications** | `GET /notifications`, `GET /notifications/unread-count`, `POST /notifications/read-all`, `PATCH /notifications/{id}/read`, `DELETE /notifications/{id}`, `GET /notifications/preferences`, `PATCH /notifications/preferences` |
| **Devices** | `POST /devices/register`, `DELETE /devices/register` |
| **Friends** | `POST /friends/requests`, `POST /friends/requests/{id}/accept`, `POST /friends/requests/{id}/decline`, `GET /friends` (friends + incoming + outgoing), `GET /friends/search?q=` (accepted friends only), `DELETE /friends/{email}`, `POST /friends/{email}/block` (204; replaces any relationship), `DELETE /friends/{email}/block` (blocker only) |
| **Shares** | `POST /shares` (share a style/prompt template with a friend, 400 if not friends or item not owned), `GET /shares/incoming`, `POST /shares/{id}/accept` (materializes an independent copy, deletes the share), `POST /shares/{id}/decline` (204) |
| **Reports** | `POST /reports` (submit a bug/feature report; optional diagnostics: `metadata`, `conversation_id`, `severity: info|warning|error`, `source: frontend|backend`), `GET /reports/mine`; admin triage: `GET /admin/reports?status=` (optional filter), `PATCH /admin/reports/{id}` (status only) |
| **Scheduled Actions** | `POST /scheduled-actions`, `GET /scheduled-actions`, `GET /scheduled-actions/{id}`, `PATCH /scheduled-actions/{id}`, `DELETE /scheduled-actions/{id}` |
| **Styles** | `POST /styles`, `GET /styles` (returns the user's saved styles plus the shared built-ins), `GET /styles/{id}`, `PATCH /styles/{id}` (built-ins: only `is_default` writable — sets a per-user default pointer; content fields 403), `DELETE /styles/{id}` (403 on built-ins) |
| **Usage** | `GET /usage/summary` |
| **Health** | `GET /health` (includes `version` — the release baked in at deploy, `APP_VERSION`) |
| **Version** | `GET /version/latest` (no auth; latest GitHub release for `GITHUB_REPO`, ~5-min cache — tag/notes/assets; feeds the desktop auto-updater) |

**MCP server scoping.** `mcp_servers.owner_email` splits servers into *global*
(NULL owner, admin-managed) and *personal* (owner = a user). `admin/mcp-servers`
CRUD only sees/touches global servers (404 on personal ones); `mcp/servers` CRUD
only sees/touches the caller's own. `GET /mcp/tools` returns global + the
caller's personal tools; rooms get global-only.

**Delegated workflows (idea 18).** The attached folder lives only on the desktop
client (idea 17), so a run works on a *server-side snapshot*: the client
uploads a copy, opencode edits that copy, and the resulting diff is **auto-
applied** by the client the moment the run reaches a terminal state — no
manual "Review changes" gate (Jorge: *"let's not have the diff review, let's
just apply"*). Undo is a separate revert native action (see IDEAS.md). That's
what lets a run outlive the client — `/start` schedules the task **outside the
request scope** and returns immediately, so closing the app doesn't cancel it;
the summary lands as an assistant message in the conversation plus an FCM
push. Every uploaded path is forced back inside the snapshot directory
server-side (absolute paths, `..`, and symlink escapes are rejected with 400),
and `workdir` is never serialized to a client. `/changes` returns each file's
`base_sha256` — the hash of what was uploaded — so the client can refuse to
overwrite a file the user edited while the run was going, reporting it as a
conflict instead.

Folderless delegation uses the same lifecycle with `scope.mode = "research"`:
`/start` git-initializes an empty server workdir, opencode receives the MCP
allowance captured from the originating conversation, and no upload, diff, or
local apply occurs. The durable `summary` is posted into chat and served as
markdown by `/output`. A leading `/agent` command forces this proposal path
instead of leaving tool choice to the chat model.
