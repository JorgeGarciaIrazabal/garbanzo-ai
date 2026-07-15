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

- `User` uses `email` as the primary key. Fields: `email`, `hashed_password`, `full_name`, `is_admin`, `is_disabled`, `default_system_prompt`, `default_model`, `created_at`.
- `Conversation.model` defaults to `"llama3.2"` — must match a model ID returned by `GET /api/v1/chat/models`.
- `Conversation.use_memory` (boolean) controls whether user memories are injected into LLM context.
- `Conversation.use_knowledge_base` (boolean) controls whether KB chunks are injected.
- `Conversation.is_pinned` (boolean) surfaces conversations in the sidebar.
- `Conversation.context_summary` stores a rolling summary to save context-window space.
- `Conversation.enabled_tools` (JSONB) stores per-conversation tool whitelists: `null` = all enabled (MCP + native), `[]` = none, `["srv:tool"]` = subset. Native garbo tools use key `"__garbo__:<tool_name>"` (e.g. `"__garbo__:scheduled_actions"`).
- `Message.meta` is JSONB and stores token counts, generation timing, thinking block content.
- `Message.role` can be: `user`, `assistant`, `system`, `tool_call`, `tool_result`.
- `UserMemory` stores extracted/manual user memories with `content`, `source_conversation_id`, `is_active`.
- `KnowledgeDocument` / `KnowledgeChunk` store uploaded documents and vector embeddings for RAG.
- `Room`, `RoomMember`, `RoomAgent`, `RoomMessage` support multi-person/agent chat rooms.
- `RoomAgent.enabled_tools` (JSONB) mirrors `Conversation.enabled_tools`: `null` = all, `[]` = none, `["srv:tool"]` = subset.
- `RoomMember.muted_until` (nullable timestamptz) suppresses push + in-app
  notifications for that member while `now() < muted_until`; messages still
  post to the room and still count as unread (WhatsApp behaviour). `NULL` =
  not muted. "Mute forever" is stored as a far-future sentinel
  (`room_service.MUTE_FOREVER`, year 9999) rather than a separate boolean
  column, so every reader — the notification skip-check in
  `room_chat_service._notify_offline_members`, the frontend badge — only ever
  needs one comparison against "now". No background job expires mutes; the
  timestamp is compared lazily at notification time.
- `ScheduledAction` stores user-defined cron or one-shot prompts.
- `Notification` / `NotificationPreferences` support in-app + FCM push notifications.
- `DeviceToken` stores FCM tokens per user per platform.
- `MCPServer` stores registered MCP server configs (managed by admin).
- `AvailableModel` stores admin-controlled per-model visibility (`model_id`, `is_enabled`).
- `SystemPromptTemplate` stores built-in and user-created prompt templates.
- Conversations use soft delete (`is_deleted=True`), not hard delete.
