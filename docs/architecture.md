# Architecture Reference

On-demand reference — read the section you need, not the whole file. For
package-local conventions see `backend/CLAUDE.md`, `lib/CLAUDE.md`,
`deploy/CLAUDE.md`. Keep this file current: update the matching section when you
change layouts, flows, or services (see "Maintaining agent docs" in the root
`CLAUDE.md`).

## Stack

- **Backend:** FastAPI (async) + SQLAlchemy/AsyncPG + PostgreSQL (pgvector) + JWT auth
- **Frontend:** Flutter (web/desktop/Android) + Provider state management + Freezed data classes
- **LLM:** Ollama (default) via a pluggable provider pattern
- **TTS:** Kokoro (in-process, loaded on backend startup)
- **STT:** Faster Whisper (in-process local by default; remote Docker fallback on port 8010)
- **Streaming:** Server-Sent Events (SSE) from backend to frontend
- **Push Notifications:** Firebase Cloud Messaging (FCM) via `fcm_service.py`
- **Scheduler:** APScheduler for daily memory extraction + user-defined scheduled actions
- **Knowledge Base:** pgvector-based semantic search (`nomic-embed-text` embeddings)
- **Rooms:** Multi-agent chat rooms with WebSocket transport (`rooms_ws.py`)

## Backend Layout (`backend/app/`)

```
core/          config.py (pydantic-settings), security.py (JWT/bcrypt),
               rate_limit.py (in-memory request throttling)
api/           microapps_proxy.py (authenticated /micro-apps reverse proxy)
api/v1/        endpoints/
               auth.py, admin.py, chat.py, devices.py, health.py,
               knowledge_base.py, mcp.py, memories.py, microapps.py,
               notifications.py, rooms.py, rooms_ws.py, scheduled_actions.py,
               stt.py, system_prompts.py, tts.py, usage.py
               →  router.py
models/        SQLAlchemy ORM:
               User, Conversation, Message, UserMemory,
               SystemPromptTemplate, MCPServer, DeviceToken,
               Notification, NotificationPreferences, ScheduledAction,
               KnowledgeDocument, KnowledgeChunk, AvailableModel,
               Room, RoomMember, RoomAgent, RoomMessage
schemas/       Pydantic I/O: auth.py, user.py, chat.py, memory.py, admin.py,
               mcp.py, system_prompt.py, device.py, notification.py,
               scheduled_action.py, usage.py, room.py, knowledge_base.py,
               microapp.py, audio.py
services/      chat_service.py (turn orchestration + tool loop)
               chat_context.py (message history + memory/KB system prompt)
               chat_title.py (conversation auto-titling)
               conversation_turn_sink.py (persists a turn's messages)
               conversation_service.py, user_service.py
               llm_provider.py (abstract base + ProviderRegistry)
               ollama_provider.py (concrete impl)
               stt_service.py, tts_service.py
               memory_service.py, memory_extraction.py
               system_prompt_service.py, mcp_service.py
               knowledge_base_service.py, embedding_provider.py, document_parser.py
               room_service.py, room_chat_service.py, room_connection_manager.py
               agent_turn.py (shared single-agent turn logic)
               scheduled_action_service.py, usage_service.py, token_counter.py
               model_management_service.py (admin model visibility)
               microapp_workspace.py, microapp_agent.py, microapp_chat_tool.py,
               microapp_registry.py (opencode-driven micro-apps workspace)
               native_tools.py (in-process chat tools: scheduled actions,
               memories, notifications — no MCP server needed)
               fcm_service.py, device_service.py, notification_service.py
               image_utils.py (image attachment resize/encoding)
db/            base.py, session.py (AsyncSession, init_db), migrations.py
jobs/          extract_memories_job.py (daily at 2 AM)
               scheduled_action_job.py (user-defined cron/one-shot actions)
               microapps_sync_job.py (periodic git pull of micro-apps repo)
scheduler.py   APScheduler lifecycle + action registration
```

### Startup sequence (`main.py`)

1. `init_db()` — create missing tables + run SQL migrations
2. `_ensure_test_user()` — create test user (if `TEST_USER_EMAIL` + `TEST_USER_PASSWORD` configured)
3. `_promote_admin_emails()` — promote matching emails to `is_admin=True`
4. `seed_builtin_templates_task()` — seed built-in system prompt templates
5. `TTSService.start_loading()` — background, non-blocking
6. `STTService.start_loading()` — background, non-blocking (skips if `stt_mode=remote`)
7. `start_scheduler()` — APScheduler for memory extraction + scheduled actions
8. `init_firebase()` — FCM push notifications (no-op if credentials missing)

### Backend notes

- Serves Flutter web from `backend/web/` in production.
- All endpoints are under `/api/v1/`. Auth uses the `get_current_user` dependency
  that validates `Authorization: Bearer <token>`.
- Adding a new LLM provider: implement the `LLMProvider` ABC in `services/` and
  register it in `ProviderRegistry`.

## Frontend Layout (`lib/`)

```
main.dart            AuthGate: checks token → routes to Login or ChatPage
                     PushService.init() at startup; registers device on login
core/
  api_client.dart    Singleton HTTP client ( dio ); resolves base URL;
                     stores token in SharedPreferences
  auth_service.dart  Singleton; login/register/logout; caches current user
  responsive.dart    Breakpoint helpers for desktop / tablet / mobile UI
features/chat/
  models/            ChatMessage, Conversation, ChatAttachment, ModelInfo,
                     ChatResponseChunk, SystemPromptTemplate, SearchResult,
                     Style, ThinkingLevel
                     ( all use freezed + json_serializable )
  providers/         ChatProvider, ModelProvider, SearchProvider,
                     SystemPromptProvider, StyleProvider
  services/          chat_service.dart (CRUD + SSE streaming),
                     audio_service.dart (STT/TTS), style_service.dart
  utils/             text_cleaner.dart (strips markdown/emojis before TTS)
  talk/              Talk Mode — full-screen hands-free voice call over
                     ChatProvider: talk_mode_page.dart, talk_mode_controller.dart
                     (state machine + call loop + voice barge-in), talk_vad.dart
                     (energy VAD), talk_recorder.dart (mic + amplitude stream),
                     talk_tts_queue.dart (sentence-streamed playback)
  widgets/           ChatPage, ChatInputWidget, ChatMessageWidget,
                     ConversationListWidget, StylePicker (StylePickerButton
                     + popover/bottom-sheet panel; replaced the old
                     ModelSelectorWidget dropdown),
                     SearchWidget, SearchResultsWidget, SystemPromptBanner,
                     SystemPromptEditorDialog, ContextWindowIndicator,
                     ContextSummaryWidget, MemoryToggleWidget,
                     RememberThisButton, EmptyChatState, ImageViewer,
                     MermaidDiagram, MarkdownWidget,
                     message/ ThinkingContent, BranchButton, EditButton,
                     RegenerateButton, SpeakButton, CopyButton,
                     MessageMetadata, MessageContent, AttachmentDisplay
features/memory/
  providers/         MemoryProvider
  pages/             MemoryPage (CRUD UI for user memories)
features/settings/
  providers/         SettingsProvider (voice, theme, auto-play toggles)
features/knowledge_base/
  pages/             KnowledgeBasePage
  providers/         KnowledgeBaseProvider
  services/          knowledge_base_service.dart
features/notifications/
  pages/             NotificationsPage
  providers/         NotificationProvider
  services/          notification_api_service.dart, push_service.dart
  models/            AppNotification
  widgets/           NotificationBell
features/usage/
  pages/             UsagePage
  providers/         UsageProvider
  services/          usage_service.dart
  models/            UsageSummary
features/rooms/
  pages/             RoomsPage, RoomChatPage
  providers/         RoomProvider
  services/          room_service.dart, room_socket_service.dart (WebSocket)
  models/            RoomModels
  widgets/           RoomsSidebar, RoomsListView, CreateRoomDialog,
                     AddAgentDialog, RoomComposeBar, RoomMessageBubble
features/admin/
  pages/             AdminPage
  providers/         AdminProvider
  services/          admin_service.dart
  models/            AdminUser, MCPServer
  widgets/           UsersTab, MCPServersTab, MCPServerDialog
features/tools/
  pages/             SkillsLibraryPage
  providers/         ToolProvider
  models/            MCPTool
features/scheduled_actions/
  pages/             ScheduledActionsPage
  providers/         ScheduledActionsProvider
  services/          scheduled_actions_api_service.dart
  models/            ScheduledAction
features/microapps/
  providers/         MicroAppPanelController
  services/          microapp_service.dart
  models/            MicroApp
  widgets/           MicroAppPanel, MicroAppView (native/web conditional impls)
pages/               LoginPage, RegisterPage
```

## Chat Message Flow

1. `ChatProvider.sendMessage()` optimistically adds the user message, then calls `ChatService.streamChatResponse()`
2. `ChatService` POSTs to `/api/v1/chat/conversations/{id}/chat` with `Accept: text/event-stream`
3. Backend `ChatService` builds message history, calls `LLMProvider.stream_chat()`, yields SSE chunks
4. **Chunk types:**
   - `chunk` — text content
   - `thinking` — reasoning / thought blocks
   - `tool_call` — MCP tool invocation requested by the assistant
   - `tool_result` — result returned from an MCP tool call
   - `done` — terminal event with metadata
   - `error` — failure metadata
5. `ChatProvider` accumulates content, upserts the assistant message live, renders tool call UI inline, then reloads conversation on `done`
6. **Regenerate** — `POST /chat/conversations/{id}/messages/{mid}/regenerate` re-streams the last assistant message
7. **Edit** — `POST /chat/conversations/{id}/messages/{mid}/edit` updates a user message and truncates all later messages, then re-streams
8. **Branch** — `POST /chat/conversations/{id}/messages/{mid}/branch` creates a new conversation from a given message ID

## SSE Streaming Protocol

Each server event: `data: {"type":"chunk","content":"...","metadata":null}\n\n`
Terminal event: `data: {"type":"done","content":null,"metadata":{...}}\n\n`
Client parses lines, strips `data: ` prefix, skips `[DONE]` sentinel.

On client disconnect mid-stream, the backend accumulates content and sends an
FCM push notification with a truncated preview.

## WebSocket Rooms (Multi-Agent)

1. `RoomSocketService` opens a WebSocket to `ws://host/rooms/{room_id}` ( authenticated via `?token=<jwt>` query param )
2. Messages are broadcast as JSON: `{ "id", "sender_user_id", "sender_agent_id", "content", "created_at", "type" }`
3. Agent responses stream over the same socket with `type="chunk"`; terminal messages have `role="assistant"`
4. REST fallback at `POST /rooms/{id}/chat` exists for smoke-testing but returns non-streaming JSON

### Room notification muting

`PATCH /rooms/{id}/members/me/mute` (`{"duration": "8h"|"1w"|"forever"|"unmute"}`)
sets `RoomMember.muted_until`; the backend skips push for members whose mute is
still in effect. NULL means not muted and a far-future sentinel
(`room_service.MUTE_FOREVER`, year 9999) means "forever", so one comparison —
`muted_until > now` — covers both. The frontend mirrors this in
`isMuteActive()` / `RoomMember.isMuted` (`rooms/models/room_models.dart`) and
renders the sentinel as "Always", never as a date.

Triggers: long-press / right-click a room in `RoomsListView`, or the bell in
the room header — both open `showMuteRoomSheet`.

`Room.mutedUntil` (the viewer's own state) is the frontend's single source of
truth — `Room.isMuted` reads it directly, no side cache. `GET /rooms` and
`/rooms/search` (`RoomOut`) populate it server-side (`viewer_email` matched
against the eager-loaded members), so the list can badge muted rooms without
opening each one. `GET /rooms/{id}` (`RoomDetailOut`) does not set this field
itself — it carries the full `members` list instead — so `RoomProvider.openRoom`
backfills `Room.mutedUntil` from `memberFor(viewerEmail)` right after
fetching. `RoomProvider.setMute` takes the PATCH response's `RoomMemberOut` and
writes it onto both the listed `Room` and `_currentRoom` via
`Room.withViewerMutedUntil`, which also keeps the matching entry in
`Room.members` in sync — so `Room.mutedUntil` and `RoomMember.mutedUntil`
never disagree about the local user after a mute/unmute round trip.

## State Management (Flutter)

Main providers per `ChatPage` tree:
- **`ModelProvider`** — available models + selected model. Kept separate so model selection survives conversation switches.
- **`StyleProvider`** — saved styles (model + thinking level + prompt template bundles, `/api/v1/styles`) plus the *pending* thinking level / system prompt the style picker composes for the next new conversation. Same survives-switches rationale as `ModelProvider`. On load it seeds the pendings from the default style (`is_default`) or, absent one, from the last saved style the user explicitly applied (id persisted locally in `SharedPreferences` via `recordLastUsed`, `style_last_used_style_id`) — an explicit default always wins over last-used. There is no backend column for "the active style": the app-bar pill and the picker's saved-style cards both derive it by matching a conversation's (or the pending) model/thinking/resolved-prompt against each saved style's settings (`_styleMatches` in `style_picker.dart`).
- **`ChatProvider`** — conversations list, current conversation + messages, streaming state. A `ChangeNotifierProxyProvider2` in `main.dart` pushes `ModelProvider.selectedModelId` and `StyleProvider`'s pending thinking/prompt into it; new conversations are created with those values. Applying a style to a live conversation is a plain conversation PATCH (model + `thinking_level` + `system_prompt`) — there is no dedicated backend endpoint.

Additional providers:
- **`MemoryProvider`** — user memories CRUD
- **`SettingsProvider`** — voice, theme, auto-play toggles; persisted via `SharedPreferences`
- **`SearchProvider`** — conversation search results
- **`SystemPromptProvider`** — system prompt template library + user default
- **`NotificationProvider`** — in-app notifications + unread count
- **`RoomProvider`** — room list, room details, room messages; mute state lives
  on `Room`/`RoomMember` themselves (see "Room notification muting" above), not
  in the provider
- **`AdminProvider`** — user admin portal (users list, MCP server management)
- **`KnowledgeBaseProvider`** — document uploads + semantic search
- **`UsageProvider`** — token usage summary
- **`ToolProvider`** — available MCP tools

## Docker Services

Dev (`docker-compose.yml`, project `garbanzo-ai`):
- **PostgreSQL** (`garbanzo_ai_postgres`) — port 5432, image `pgvector/pgvector:pg16`, credentials `garbanzo:garbanzo_dev`, database `garbanzo_ai`
- **Faster Whisper Server** (`garbanzo_ai_whisper`) — port 8010, CPU-based STT via `fedirz/faster-whisper-server:latest-cpu` (only used when `STT_MODE=remote`)

Prod (`deploy/docker-compose.yml`, project `garbanzo-prod` — fully separate DB/volumes/network): see `deploy/CLAUDE.md` and `deploy/README.md`.

> Kokoro TTS runs **in-process** in the backend (not a Docker service). STT can
> also run in-process (`stt_mode=local`, the default) bypassing the Docker
> container entirely.
