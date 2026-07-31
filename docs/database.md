# Database Reference

PostgreSQL with the `pgvector` extension (embeddings). ORM models live in
`backend/app/models/`. Keep this file current: new models or columns with
non-obvious semantics get a bullet here in the same commit.

## Migrations (no Alembic)

Schema comes from two automatic steps at backend startup (`init_db()`):

1. `Base.metadata.create_all()` — creates missing tables (never alters existing ones).
2. `run_migrations()` (`backend/app/db/migrations.py`) — applies
   `backend/migrations/*.sql` in filename order, once each, tracked in a
   `schema_migrations` table.

When a SQLAlchemy model gains a new column, add an idempotent SQL file to
`backend/migrations/` following the naming pattern `NNN_description.sql`
(e.g. `012_add_title.sql`). Always use `ADD COLUMN IF NOT EXISTS`. Every
database (dev and prod) picks it up on the next backend start. A failing
migration intentionally crashes the backend at startup so it never serves a
half-migrated schema.

## Model Notes

- `User` uses `email` as the primary key. Fields: `email`, `hashed_password`, `full_name`, `is_admin`, `is_disabled`, `default_system_prompt`, `default_model`, `profile_picture_b64`, `timezone`, `locale`, `created_at`.
- `User.timezone` (nullable IANA zone name) / `User.locale` (nullable BCP 47
  tag) are reported by the client via `PATCH /auth/me` and feed the dynamic
  `<context>` block (`chat_context.build_dynamic_context_block`) injected
  into every chat turn's system prompt so "today"/"this weekend" resolve in
  the user's local time. Persisted on the user rather than sent per-request
  so server-initiated turns (room agents, scheduled actions) know the
  timezone too. Validated against the server's `zoneinfo` at the API
  boundary (`UserUpdate.validate_timezone`); plain VARCHAR in the DB since
  the IANA registry evolves. `NULL` = never reported → the block carries
  only server UTC time.
- `User.location` (nullable VARCHAR) is the opt-in coarse location for the
  same `<context>` block — always a human-readable "City, Country" string,
  never coordinates. Set either by `POST /auth/me/location` (client sends
  coordinates once; `services/geocoding.py` reverse-geocodes city-level via
  Nominatim, `NOMINATIM_URL` env, and only the result is stored) or manually
  via `PATCH /auth/me`. `NULL` = sharing off (the settings toggle's default
  and its "off" state) → no location line in the prompt.
- `Conversation.model` defaults to `DEFAULT_MODEL` (`"minimax-m3:cloud"` by
  default) — it must match a model ID returned by `GET /api/v1/chat/models`.
- `Conversation.use_memory` (boolean) controls whether user memories are injected into LLM context.
- `Conversation.use_knowledge_base` (boolean) controls whether KB chunks are injected.
- `Conversation.is_pinned` (boolean) surfaces conversations in the sidebar.
- `Conversation.context_summary` stores a rolling summary to save context-window space.
- `Conversation.enabled_tools` (JSONB) stores per-conversation tool whitelists: `null` = all enabled (MCP + native), `[]` = none, `["srv:tool"]` = subset. Native garbo tools use key `"__garbo__:<tool_name>"` (e.g. `"__garbo__:scheduled_actions"`).
- `Message.meta` is JSONB and stores token counts, generation timing, thinking block content.
- `Message.role` can be: `user`, `assistant`, `system`, `tool_call`, `tool_result`.
- `Message.seq` (B-03) is an app-assigned monotonic insertion order
  (`time.time_ns()` at construction), used to paginate a conversation's
  messages. `created_at` alone can't serve as a pagination cursor — rows
  persisted within the same DB transaction (an agent turn's
  assistant/tool_call/tool_result rows) share an identical value, since
  Postgres `now()` is transaction-start time, not per-statement time.
  NOT NULL at the schema level (migration 025) — pagination orders by
  `seq DESC` and Postgres sorts NULLs first in DESC, so a stray NULL row
  would masquerade as the newest message.
- `UserMemory` stores extracted/manual user memories with `content`, `source_conversation_id`, `is_active`.
- `KnowledgeDocument` / `KnowledgeChunk` store uploaded documents and vector embeddings for RAG.
- `Room`, `RoomMember`, `RoomAgent`, `RoomMessage` support multi-person/agent chat rooms.
- `RoomAudioNote` stores the raw WAV bytes, MIME type, and duration for one
  `RoomMessage` (unique FK, cascade delete). The message content is the visible
  STT transcript used by room agents; `RoomMessage.meta.audio_note` carries only
  the note id/MIME/duration so message lists never embed multi-megabyte audio.
- `Friendship` (Idea 5) — one row per relationship, directional at request
  time (`requester_email` → `addressee_email`), status
  `pending`/`accepted`/`blocked` (plain VARCHAR, validated at the API
  boundary). Decline/remove DELETE the row so either side can retry;
  blocked rows persist; `block()` reorients the row so `requester_email` is
  always the blocker (only they see it in `GET /friends` `blocked` and only
  they can unblock — the blocked side never learns a block exists). Rooms
  respect blocks: a blocked pair can't be put in a room together by either
  party (`RoomService._blocked_pair_exists`, generic 403). A unique index on
  the
  (requester, addressee) pair plus service-level reverse-direction handling
  (a request answering an existing reverse pending accepts it) keep at most
  one row per pair. `GET /friends/search` only searches accepted friends —
  never the users table — so the API can't be used for account enumeration
  (the one deliberate disclosure is exact-match existence when sending a
  request).
- `SharedItem` (Idea 9) — one row per pending share: `sender_email`,
  `recipient_email`, `kind` (`style`/`prompt`), and `payload` (JSONB
  snapshot of the shared item's content). Sharing requires an accepted
  `Friendship` between the two emails. Accepting materializes an
  independent copy from `payload` (a new `Style`/`SystemPromptTemplate`
  owned by the recipient) and deletes the row — there is no live link back
  to the original, so edits or deletes on the sender's side afterwards
  never affect the recipient's copy. Declining just deletes the row.
- `RoomAgent.enabled_tools` (JSONB) mirrors `Conversation.enabled_tools`: `null` = all, `[]` = none, `["srv:tool"]` = subset.
- `RoomAgent.thinking_level` mirrors `Conversation.thinking_level`
  (`off`/`low`/`medium`/`high`, `NULL` = provider default); passed as
  `ChatOptions.think` on the agent's turns.
- `RoomMember.muted_until` (nullable timestamptz) suppresses push + in-app
  notifications for that member while `now() < muted_until`; messages still
  post to the room and still count as unread (WhatsApp behaviour). `NULL` =
  not muted. "Mute forever" is stored as a far-future sentinel
  (`room_service.MUTE_FOREVER`, year 9999) rather than a separate boolean
  column, so every reader — the notification skip-check in
  `room_chat_service._notify_offline_members`, the frontend badge — only ever
  needs one comparison against "now". No background job expires mutes; the
  timestamp is compared lazily at notification time. The viewer's own
  `muted_until` also surfaces on the list/search response (`RoomOut`, not just
  `RoomDetailOut.members[].muted_until`) so the room-list sidebar can badge
  muted rooms without fetching each room's full member list — populated by
  `RoomOut.from_model(room, viewer_email=...)` scanning the (already
  eager-loaded) `room.members` for the caller's own row; `None` when
  `viewer_email` is omitted or the viewer isn't a member.
- `Conversation.thinking_level` (nullable, one of `off`/`low`/`medium`/`high`)
  controls reasoning depth for thinking-capable models (Idea 2: "Styles").
  `NULL` preserves the implicit pre-existing behavior — `ollama_provider`
  auto-enables thinking (`think=True`) whenever the model advertises the
  `thinking` capability. An explicit value overrides that: `off`
  force-disables thinking even for a capable model; `low`/`medium`/`high`
  map straight onto Ollama's `think` chat option, which the installed
  `ollama-py` SDK types as `bool | Literal["low", "medium", "high"]`
  (`ollama/_types.py`). Set from `chat_service._stream_assistant_turn` onto
  `ChatOptions.think` right before every provider call — it always wins over
  whatever a client's request-level `ChatOptions` carried, since clients
  aren't expected to set `think` directly. Either way, the value is only
  ever sent to Ollama for models that advertise the `thinking` capability
  (`ModelInfo.supports_thinking` on `GET /chat/models`, already computed by
  `OllamaProvider.list_models`); this task deliberately did not add a
  separate "does this model support thinking" flag/endpoint since one
  already exists — a later task (Idea 2 subtask 5) extends `GET
  /chat/models` with more capability flags (`supports_tools`,
  `supports_vision`) alongside it.
- Idea 17 ("include a folder in a chat") deliberately stores **nothing** in the
  DB: the attached folder lives only on the desktop client (SharedPreferences),
  so the backend never learns or reads a host path. Each chat request sets
  `has_client_folder` to advertise the client-served `read_file`/`list_files`
  tools; reads are delegated back to the client at turn time via a
  `client_tool_request` SSE chunk + the `POST …/client-tool-result` endpoint
  (bridged in-process by `ClientToolBridge`).
- `ScheduledAction` stores user-defined cron or one-shot prompts.
  `conversation_id` (migration 034; user-report 89b954f7) optionally pins
  a recurring action to a single conversation so its run history
  accumulates in one chat instead of spawning a new conversation each fire.
  Set on the first run; NULL for one-off (`run_at`) actions. `ON DELETE SET
  NULL` so deleting the conversation lets the next run start a fresh one.
- `User.default_style_id` (migration 035; user-report f1af13d5) is the
  per-user default style for new conversations — a reference to any
  *visible* style (built-in or user-owned), so a shared built-in like
  "Truth Seeker" can be a user's default without mutating the shared row
  (which would affect every user). `ON DELETE SET NULL`. The response's
  `style.is_default` is recomputed per-user from this pointer by
  `StyleService`; the stored `Style.is_default` column + its partial
  unique index are vestigial legacy, kept only so older code paths that
  still set `Style.is_default` stay consistent.
- `Report` (026; extended by 033, idea 22) stores in-app bug reports / feature requests:
  `type` is `bug|feature`, `status` flows `open → in_progress → closed` and is
  admin-controlled (`PATCH /admin/reports/{id}`); values are enforced by
  Pydantic literals, not DB enums, matching how other string states are
  handled. User-owned via `user_id → users.email` CASCADE. Automatic error
  reports additionally store nullable `metadata` JSONB (trace/context), indexed
  `conversation_id` (a navigation hint, not an FK), `severity`, and `source`
  (`frontend|backend`); manual reports leave them NULL.
- `Notification` / `NotificationPreferences` support in-app + FCM push notifications.
- `DeviceToken` stores FCM tokens per user per platform.
- `MCPServer` stores registered MCP server configs. `owner_email` (nullable FK,
  ON DELETE CASCADE) sets scope: `NULL` = global (admin-managed, tools offered to
  everyone and to rooms); set = personal to that user (tools offered only to that
  user's chats, never rooms). `created_by` is audit-only (SET NULL).
- `AvailableModel` stores admin-controlled per-model visibility (`model_id`, `is_enabled`).
- `SystemPromptTemplate` stores built-in and user-created prompt templates.
  Built-in rows carry a non-null `locale` (BCP-47 primary subtag, e.g. `en` /
  `es` — seeded in both languages) so the picker can filter by the user's UI
  language; user-saved rows keep `locale = NULL` (language-neutral, surface in
  every locale). Added by 028_system_prompt_locale.sql; existing English
  builtins are retroactively tagged `en` by the migration.
- `Style` (Idea 2: "Styles", subtask 2) is a saved, reusable bundle of
  `model_id` + `thinking_level` + `system_prompt_template_id` a user can name
  ("Deep Work", "Quick Answers") and reuse across conversations — the picker
  UI and per-conversation "apply a style" wiring are later subtasks. A style
  is either owned by a user (`user_id` = their email) or shared as a
  **built-in** (`user_id = NULL`, `is_builtin = TRUE`); built-ins are seeded
  by `StyleService.seed_builtin_styles` at startup from
  `StyleService.BUILTIN_STYLES` (six per supported locale — Concise, Truth
  Seeker, Writing & Stories, Coding, Tutoring, Brainstorm in English; the
  same six named in Spanish), each referencing a built-in
  `SystemPromptTemplate` of the same `(name, locale)` as its prompt half.
  They surface in the picker as one-tap cards above the user's own styles
  and are read-only — `StyleService.update`/`delete` raise
  `BuiltinReadOnlyError` (the endpoint maps to 403). `locale` on built-ins
  holds the BCP-47 tag ('en'/'es') so the picker surfaces them in the user's
  language; user-saved rows keep `locale = NULL` (language-neutral, surface
  in every locale). `description` is a short subtitle shown under the
  built-in's name in the card (e.g. "Short, direct, to-the-point
  answers"). All three columns added by 030_styles_builtin.sql; the
  migration also makes `user_id` nullable so a built-in can exist (`NULL`
  never matches a user row, so the partial unique index
  `ix_styles_one_default_per_user` — which keys on `user_id` — never
  collides with a built-in; built-ins are never marked `is_default`
  anyway).
  `thinking_level` reuses the exact `off`/`low`/`medium`/`high`
  representation as `Conversation.thinking_level` above (shared Pydantic
  `ThinkingLevel` literal in `app/schemas/chat.py`, not redefined).
  `system_prompt_template_id` is nullable with `ON DELETE SET NULL`
  (018_styles.sql): deleting the referenced template only clears that
  half of the bundle — it never cascades to delete the style itself, since
  the model/thinking-level choices remain meaningful on their own (mirrors
  `UserMemory.source_conversation_id`). `is_default` marks the style used to
  seed new conversations; at most one per user is enforced by a partial
  unique index (`ix_styles_one_default_per_user`), with `StyleService`
  unsetting any prior default before setting a new one so callers don't hit
  the constraint in normal use.
- Conversations use soft delete (`is_deleted=True`), not hard delete.
- `WorkflowRun` (032_workflow_runs.sql) is one delegated opencode run (idea
  18). It exists because the run is **detached**: it keeps going after the
  client that started it disconnects, so its state can't live in the SSE
  stream. `status` flows `draft` → `uploading` → `queued` → `running` →
  `done` | `error` | `cancelled`.
  - `scope.mode` is `"folder"` or `"research"` (missing on legacy rows means
    folder). Folder runs upload a snapshot and return a diff. Research runs
    start empty, skip diff/apply, and expose `summary` as markdown.
    `scope.mcp_tools` captures the conversation MCP whitelist (`null` = all
    visible, `[]` = none) without storing connection credentials on the run.
  - `workdir` is the absolute path of the server-side folder snapshot or empty
    research scratch directory, git-init'd at `/start`. It is internal and
    never serialized. Folder mode releases it after `/applied`; research
    releases it as soon as the terminal summary is persisted.
  - `progress` (JSONB) is the appended list of translated opencode chunks,
    replayed via `GET /{id}?since=<n>`. Streamed text is coalesced into the
    previous entry and the list is capped (2000 entries) so a runaway run
    can't bloat the row.
  - `tool_call_id` is the `delegate_workflow` proposal's id, which is how a
    proposal card re-finds its run after a reload — no client-side storage
    needed for the *run* itself. The **applied/not-applied** flag the
    auto-apply path needs (so a reload doesn't double-write the diff) is kept
    client-side in `SharedPreferences` keyed by run id; the run row never
    learns whether the diff has landed on the user's disk.
  - `conversation_id` is nullable for room-originated runs; when set, the
    final summary is written back as an assistant `Message` carrying
    `meta.workflow_run_id`.
  - Runs left in `queued`/`running` by a backend restart are swept to
    `error` at startup (`main._fail_stale_workflow_runs`) — their opencode
    subprocess died with the old process, so a polling client would
    otherwise wait forever.
