# API Endpoint Reference

All endpoints are prefixed with `/api/v1/`. Auth uses the `get_current_user`
dependency validating `Authorization: Bearer <token>`. Keep this table current:
when you add or change an endpoint, update the matching row in the same commit.

| Group | Endpoints |
|-------|-----------|
| **Auth** | `POST /auth/login`, `POST /auth/register` (disabled, 403), `POST /auth/refresh`, `GET /auth/me`, `PATCH /auth/me` (profile incl. `timezone`/`locale`/`location`), `POST /auth/me/location` (coords → reverse-geocoded city, coords never stored), `POST /auth/me/password`, `POST /auth/me/avatar`, `DELETE /auth/me/avatar` |
| **Admin** | `POST /admin/users`, `GET /admin/users`, `PATCH /admin/users/{email}`, `GET /admin/mcp-servers`, `POST /admin/mcp-servers`, `PATCH /admin/mcp-servers/{id}`, `DELETE /admin/mcp-servers/{id}`, `POST /admin/mcp-servers/{id}/test-connection`, `GET /admin/models`, `POST /admin/models/sync`, `PATCH /admin/models` |
| **Chat** | `GET/POST /chat/conversations`, `POST /chat/conversations/primary` (idempotently ensure the user's unified primary conversation), `GET /chat/conversations/search`, `GET /chat/conversations/{id}` (optional `message_limit` — most-recent-N window instead of full history, B-03), `GET /chat/conversations/{id}/messages?before=&limit=` (page in older messages), `PATCH /chat/conversations/{id}`, `PATCH /chat/conversations/{id}/mute`, `POST /chat/conversations/{id}/client-tool-result` (desktop client returns an on-demand folder read — idea 17; body `{tool_call_id, ok, filename?, data?(base64), entries?, error?}`), `DELETE /chat/conversations/{id}`, `POST /chat/conversations/{id}/chat` (SSE stream whose detached producer finishes if the client disconnects; `has_client_folder` advertises client-served read tools; optional `talk_mode_instruction` adds localized ephemeral system context for that turn; images sent to a known text-only model return `error_type=unsupported_image_input`; primary turns may begin with `topic_update`, `context_preparing`, and `context_update` metadata-only events), `POST /chat/conversations/{id}/messages/{mid}/regenerate` (detached SSE), `POST /chat/conversations/{id}/messages/{mid}/edit` (detached SSE), `POST /chat/conversations/{id}/messages/{mid}/branch`, `DELETE /chat/conversations/{id}/chat` (cancel stream), `GET /chat/models` (includes provider-reported `thinking_levels` and `default_thinking_level` when known), `GET /chat/health/llm` |
| **Topics & Context** | `GET /chat/topics?mode=personal|explore`, `POST /chat/conversations/{id}/topics/activate`, `POST /chat/conversations/{id}/topics/switch` (switch primary topic, archive old thread, clear messages, rebuild context, seed carryover), `PATCH /chat/conversations/{id}/topic` (select/clear/pin the primary topic), `GET /chat/topics/{topic_id}/context-status`, `POST /chat/topics/{topic_id}/prepare`, `GET /chat/conversations/{id}/context`, `POST /chat/conversations/{id}/context/items`, `PATCH /chat/conversations/{id}/context/items/{item_id}`, `POST /chat/conversations/{id}/context/fresh-start`, `GET /chat/topics/{topic_id}/archives` (list archived primary threads attached to a topic) |
| **System Prompts** | `GET /system-prompts/templates` (optional `?locale=` query — filters builtins to the requested language when one is seeded for it; user-saved templates always surface), `POST /system-prompts/templates`, `PATCH /system-prompts/templates/{id}`, `DELETE /system-prompts/templates/{id}`, `GET /system-prompts/user-default`, `PUT /system-prompts/user-default`, `POST /system-prompts/generate` (SSE stream) |
| **STT** | `POST /stt/transcribe` (optional `language` form field — ISO code or `"auto"`/omitted for per-clip detection, idea 13), `GET /stt/health` |
| **TTS** | `POST /tts/speak`, `POST /tts/speak/stream` (text is limited to 5,000 characters per request; both take optional `language` — ISO code; swaps in that language's default voice when `voice` doesn't speak it, idea 13), `GET /tts/voices` (each voice carries `language` + ISO `lang_code`; en/es/fr/hi/it/pt), `GET /tts/health` |
| **Memories** | `POST /memories`, `GET /memories`, `GET /memories/{id}`, `PATCH /memories/{id}`, `DELETE /memories/{id}` |
| **Knowledge Base** | `POST /kb/documents`, `GET /kb/documents`, `GET /kb/documents/{id}`, `DELETE /kb/documents/{id}`, `GET /kb/search` |
| **Rooms** | `POST /rooms`, `GET /rooms`, `GET /rooms/search`, `GET /rooms/{id}`, `PATCH /rooms/{id}`, `DELETE /rooms/{id}`, `GET /rooms/{id}/members`, `POST /rooms/{id}/members`, `DELETE /rooms/{id}/members/{email}`, `PATCH /rooms/{id}/members/me/mute`, `GET /rooms/{id}/agents`, `POST /rooms/{id}/agents`, `PATCH /rooms/{id}/agents/{id}`, `DELETE /rooms/{id}/agents/{id}`, `GET /rooms/{id}/messages`, `POST /rooms/{id}/chat`, `POST /rooms/{id}/audio-notes` (multipart 16 kHz mono WAV, ≤2 min; transcribes, persists, and starts detached agent turns), `GET /rooms/{id}/audio-notes/{note_id}` (member-only raw playback), `GET /rooms/{id}/export`, `WS /rooms/{id}` |
| **Micro-apps** | `POST /microapps/workspace`, `GET /microapps/workspace`, `DELETE /microapps/workspace`, `GET /microapps/apps`, `GET /microapps/houses`, `POST /microapps/houses`, `POST /microapps/agent/chat`, `POST /microapps/agent/abort`, `GET /microapps/changes`, `POST /microapps/publish`, `POST /microapps/revert` |
| **Workflows** | `POST /workflows` (create a delegated opencode run in `draft`; body `{instruction, mode:"folder"|"research", conversation_id?, room_id?, tool_call_id?, folder_label?}`; an owned conversation imports the launching user message's attachments into the isolated workspace), `GET /workflows?conversation_id=` (hydrate proposal cards after reload), `POST /workflows/{id}/files` (folder mode only: upload a snapshot batch), `POST /workflows/{id}/start` (git-baseline the folder snapshot or attachment-backed research workdir and launch the **detached** run), `GET /workflows/{id}?since=` (status + progress after the cursor), `GET /workflows/{id}/changes` and `POST /workflows/{id}/applied` (folder mode diff/cleanup), `GET /workflows/{id}/output` (completed research mode: markdown summary attachment) |
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
| **Version** | `GET /version/latest` (no auth; latest GitHub release for `GITHUB_REPO`, ~5-min cache — tag/notes/assets; feeds Linux, Windows, and Android auto-updaters) |

### Primary-chat topic/context behavior

`POST /chat/conversations/primary` ensures the single primary (else legacy thread); `GET ?kind=primary|thread|all` filters. Compiler runs only for primary when `TOPIC_CONTEXT_ENABLED`. Legacy/regenerate/edit/tool loops keep old path.

Primary SSE may prefix 3 metadata-only events (`schema_version:1`) before first token:
`topic_update` (`context_version`, `topic{id,label,parent_id,parent_label,description,pinned}`, `reason`),
`context_preparing` (`context_version`, `state:preparing`, topic),
`context_update` (counts, budget, `pack{id,version,watermark}|null`, `freshness:ready|live|preparing`); `done` includes `context_snapshot`. `GET /chat/conversations/{id}/context` returns high-level synthesized `topic_description`, `context_summary`, and declarative `context_sections` ("Topic Scope & Purpose", "Information Included in Context") rather than raw message transcripts or provenance IDs. Compiler overlays valid pack + live assertions + pins + recent evidence, filters ownership/deletion/validity/exclusion, falls back to bounded raw evidence if stale — never blocks answer. No DeepSeek curator provider in this release.

**MCP server scoping.** `mcp_servers.owner_email` splits servers into *global*
(NULL owner, admin-managed) and *personal* (owner = a user). `admin/mcp-servers`
CRUD only sees/touches global servers (404 on personal ones); `mcp/servers` CRUD
only sees/touches the caller's own. `GET /mcp/tools` returns global + the
caller's personal tools; rooms get global-only.

**Delegated workflows (idea 18).** Folder lives only on desktop (idea 17); run works on server snapshot uploaded by client, opencode edits copy, diff is auto-applied — no review gate (`/start` is detached, survives client close, summary → assistant message + FCM). Paths forced inside snapshot (400 on `..`/abs/symlink), `workdir` never serialized, `/changes` returns `base_sha256` for conflict check. Research mode (`scope.mode=research`): no upload/diff, git-init workdir, MCP allowance from conversation, summary → `/output`; leading `/agent` forces it. `POST /workflows` copies attachments to `.garbanzo-workflow-inputs/` (5 MB/file, 50 MB/run, Unicode-safe) — reserved dir excluded from snapshot/diff.

### Topic switch flow

`POST /chat/conversations/{id}/topics/switch` is the single entry point for
changing the active topic in the primary conversation. It performs these
steps atomically:

1. **Archive** — If `archive: true` (default), snapshots the entire current
   primary message history into a `topic_archives` row attached to the *old*
   topic so a future "enhance this topic" pass can re-derive evidence without
   the live primary conversation.
2. **Clear** — Deletes all messages from the primary conversation and
   clears all active-context items (pins + dynamic) for that conversation.
   Each message deletion is enqueued as a `delete` ingestion event so the
   topic pipeline invalidates prior evidence.
3. **Activate** — Creates or attaches the new topic (same semantics as
   `activate` endpoint), bumps `context_version`, and pins the new topic.
4. **Carryover** — If `carryover.enabled: true` (default), runs a bounded
   LLM call (`carryover_max_items`, `carryover_max_tokens`) against the just-
   archived messages to extract the most important facts/decisions/preferences.
   Output is validated against a strict schema; on any failure a deterministic
   fallback uses the most recent user messages. Carryover items are written
   as `ActiveContextItem` rows with `source_type = "carryover"` so the UI
   renders them as a dedicated "Carryover" branch in the context tree.
5. **Prepare** — Kicks off an async pack build for the new topic (does not
   block the response). The next user turn will receive fresh `topic_update`,
   `context_update`, and `context_snapshot` SSE events.

Response returns the new topic, `context_version`, `archived` boolean,
`archive_id` (if created), the `carryover` items, and a `next_turn_summary`.
If the conversation is not primary or the topic is not owned, returns 409/404.
