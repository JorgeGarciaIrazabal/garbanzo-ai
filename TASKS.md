# Garbanzo AI — Feature Backlog

## Voice (TTS / STT)

<!--
STT model research (2025):
  Primary:   faster-whisper large-v3 (MIT, CPU-viable, 100+ langs, 4x faster than original Whisper)
             → wrap with faster-whisper-server for a drop-in REST endpoint
  GPU boost: NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0, RTFx >2000, English + 25 EU langs, needs CUDA)
  Edge/CPU:  whisper.cpp (MIT, pure C++, built-in HTTP server, runs on anything incl. Raspberry Pi)

TTS model research (2025):
  Primary:   Kokoro-82M (Apache 2.0, 82M params, 210x GPU / 3-5x CPU realtime, 8 langs, 48 voices)
             → deploy via kokoro-fastapi which exposes /v1/audio/speech (OpenAI-compatible)
  Cloning:   Chatterbox Turbo (MIT, zero-shot voice cloning from 5s clip, sub-200ms latency, 23 langs)
  CPU-only:  Piper TTS (MIT, ONNX, real-time on Raspberry Pi, 900+ voice models, 30+ langs)
  Avoid:     Coqui XTTS v2 — company shut down Dec 2025, non-commercial license
             OpenAI TTS/Whisper API — proprietary, not self-hosted
-->

- [x] **STT: Microphone input** — Record audio in the chat input widget with a hold-to-talk / tap-to-toggle button; use Flutter `record` package
- [x] **STT: faster-whisper service** — Dockerized `faster-whisper-server` (MIT) exposing `POST /v1/audio/transcriptions`; defaults to `large-v3`; swap for Parakeet TDT 0.6B v3 if an NVIDIA GPU is present
- [x] **STT: Backend transcription endpoint** — `POST /api/v1/stt/transcribe` that forwards audio to the faster-whisper service and returns the transcript text
- [x] **STT: Auto-submit after transcription** — Option to auto-send the message once voice input stops and transcription completes
- [x] **TTS: Kokoro-82M service** — Dockerized `kokoro-fastapi` (Apache 2.0) exposing `/v1/audio/speech` (OpenAI-compatible); 48 voices across 8 languages
- [x] **TTS: Backend speech endpoint** — `POST /api/v1/tts/speak` that proxies to Kokoro and streams audio back to the client
- [x] **TTS: Per-message playback** — Play/stop button on each assistant message that calls the TTS endpoint and streams audio via the Flutter `audioplayers` package
- [x] **TTS: Auto-play mode** — Setting to auto-play TTS for every new assistant message as it finishes streaming
- [x] **TTS/STT: Voice settings UI** — Settings panel to choose: STT model (faster-whisper / Parakeet), TTS voice (from Kokoro's 48 voices), TTS language, and speaking speed
- [ ] **TTS: Chatterbox Turbo voice cloning** — Optional: allow users to upload a 5-second voice sample; backend forwards to a Chatterbox Turbo service for personalized TTS output (MIT license)
- [x] **TTS: Clean up text for better speech** — Strip markdown formatting (#, **, `, code blocks, links) and emojis before sending text to TTS

## File & Image Upload (enhancements)
- [x] **Image viewer** — Full-size lightbox when clicking image attachments in messages
- [x] **PDF text extraction** — Use `pypdf` on the backend to extract text from PDFs before sending to LLM
- [x] **Spreadsheet/CSV support** — Parse and summarize tabular data in attachments
- [x] **Drag-and-drop upload** — Drag files directly onto the chat window
- [x] **Paste image from clipboard** — Ctrl+V to attach a copied screenshot
- [x] **File size/type validation** — Clear UX errors with limits per type
- [x] **Multiple file attachments at once** — Batch select in the file picker

## Memory (ChatGPT-like)
- [x] **Memory store DB model** — `UserMemory` table: id, user_id, content, source_conversation_id, created_at, is_active
- [x] **Auto-extract memories** — cron job after every day; LLM call to extract facts about the user worth remembering
- [x] **Memory injection** — Prepend relevant memories to system prompt on each request
- [x] **Memory management UI** — `/memory` page to view, edit, and delete memories
- [x] **Manual memory creation** — "Remember this" button/command in chat
- [x] **Memory toggle per conversation** — Option to disable memory for a specific conversation

## System Prompt (The first iterations of agents)
- [x] **Per-conversation system prompt** — Editable in conversation settings panel
- [x] **Global default system prompt** — Set in user settings, applied to all new conversations
- [x] **System prompt templates** — Pre-built personas (Coding assistant, Writing coach, Funny Friend, Emotional Expert,etc.)
- [x] **System prompt library** — Save and reuse custom prompts
- [x] **System prompt visibility** — Option to show/collapse system prompt in the message thread

## MCP / Tools / Skills (Admin Portal)
- [x] **Admin portal foundation** — `/admin` route, restricted to `is_admin=True` users; user table migration
- [x] **MCP server configuration UI** — Add/remove/toggle MCP server connections (URL, auth, description)
- [x] **Tool execution backend** — Tool call loop: LLM requests tool → backend invokes MCP server → result fed back into context
- [x] **Tool results display in chat** — Collapsible "Tool Used" block showing name, input, output
- [x] **Skills library UI** — Browse available skills/tools from connected MCP servers
- [x] **Per-conversation tool selection** — Toggle which tools are enabled for a conversation
- [x] **Admin: User management** — List, promote, disable users from admin portal

## Notifications (Android-oriented)
> Also used to notify participants in multi-user, multi-agent chat rooms (e.g., new messages from other users or agent responses while away).

- [ ] **Android Push notifications (FCM)** — Firebase Cloud Messaging setup; notify when a long-running response completes while app is in background
- [ ] **Android notification channels** — Separate channels for chat responses, reminders, and system alerts with per-channel importance levels
- [ ] **Backend FCM integration** — Store device tokens per user; send push via Firebase Admin SDK when SSE stream completes and client is disconnected
- [ ] **In-app notification center** — Bell icon with read/unread notifications list
- [ ] **Notification preferences** — Per-user settings for which events trigger notifications, synced with Android channel settings

## Scheduled Actions
- [ ] **Scheduled messages** — "Remind me to do X at 3pm" parsed and stored as a cron job
- [ ] **Recurring prompts** — Daily/weekly AI check-ins (e.g., "Summarize my tasks every Monday")
- [ ] **Scheduled action DB model** — `ScheduledAction` table: id, user_id, cron_expr, prompt, next_run, is_active
- [ ] **APScheduler integration** — Backend scheduler to execute due actions and create conversations
- [ ] **Scheduled actions management UI** — List, pause, delete scheduled actions

## Conversation UX
- [ ] **Message editing** — Edit a sent user message and re-run from that point
- [ ] **Message regeneration** — "Regenerate" button to re-run the last assistant response
- [ ] **Message branching** — Fork conversation from any message into a new branch
- [ ] **Conversation search** — Full-text search across all conversations and messages
- [ ] **Conversation export** — Download as Markdown, JSON, or PDF
- [ ] **Conversation sharing** — Generate a read-only shareable link
- [ ] **Conversation folders / tags** — Organize conversations into named groups
- [ ] **Pinned conversations** — Pin important conversations to the top of the sidebar
- [ ] **Conversation templates** — Start a new chat from a saved template (prompt + system prompt + model)
- [ ] **Message reactions / starring** — Star or bookmark individual messages

## UI / Rendering
- [x] **Markdown rendering** — Full CommonMark support (tables, footnotes, task lists)
- [x] **Code syntax highlighting** — `flutter_highlight` or `google_code_prettify`; copy-code button per block
- [x] **Math/LaTeX rendering** — `flutter_math_fork` for inline and block equations
- [x] **Mermaid diagrams** — Render diagram code blocks as SVG
- [ ] **Artifacts panel** — Side-by-side panel for rendered HTML/code output (like Claude artifacts)
- [x] **Dark / light / system theme** — Theme toggle in settings, persisted in SharedPreferences
- [x] **Message metadata** — Toggle to show/hide message metadata (tokens, time for response, etc.)

## Settings & Profile
- [ ] **User settings page** — Dedicated `/settings` route with sections: Profile, Appearance, Models, Voice, Memory, Notifications
- [ ] **Profile editing** — Update name and email; change password
- [ ] **Default model preference** — Persisted per-user default model (DB, not just local state)
- [ ] **Token usage dashboard** — Charts showing token consumption by model, conversation, and time period

## Knowledge Base / RAG
- [ ] **Knowledge base uploads** — Upload documents that persist across all conversations
- [ ] **pgvector integration** — Vector embeddings for semantic retrieval
- [ ] **Embedding generation** — Background job to chunk and embed uploaded documents
- [ ] **RAG injection** — Retrieve relevant chunks and inject into context before each request
- [ ] **Knowledge base management UI** — Upload, view, delete documents in the knowledge base

## Context Management
- [x] **Context window indicator** — Visual token count showing how full the context window is
- [x] **Auto-summarization** — When context approaches the limit, summarize old messages and trim
- [x] **Conversation summary view** — Collapsible "Summary of earlier messages" block in thread

## Multi-Person & Multi-Agent Chat Rooms
- [ ] **Room DB model** — `Room` table: id, name, description, owner_id, created_at; `RoomMember` table: room_id, user_id, role (owner/member), joined_at
- [ ] **Room agent slots** — `RoomAgent` table: room_id, agent_name, system_prompt, model, provider, turn_order, is_active
- [ ] **WebSocket support** — Replace or extend SSE with WebSocket connections so multiple users receive messages in real time
- [ ] **Room creation UI** — Create a named room, set description, invite members by email
- [ ] **Room member management** — Add/remove members, assign roles, transfer ownership
- [ ] **Agent configuration UI** — Add AI agents to a room: pick name, avatar, model, system prompt, and when they respond (always, when @mentioned, round-robin)
- [ ] **@mention routing** — `@AgentName` in a message triggers only that agent to respond; `@all` triggers all agents
- [ ] **Round-robin agent turns** — Configurable mode where agents respond in sequence automatically
- [ ] **Agent-to-agent conversations** — Agents can see and respond to each other's messages; configurable max turn depth to prevent infinite loops
- [ ] **Moderator agent** — Special agent role that summarizes discussion, breaks deadlocks, or routes questions to the right agent
- [ ] **Room message history** — Shared scrollback visible to all members with author avatars (human vs agent)
- [ ] **Presence indicators** — Show which users are currently online in the room
- [ ] **Room notifications** — Notify members when they are @mentioned or when a new message arrives
- [ ] **Room search & discovery** — Browse and join public rooms; private rooms require invite
- [ ] **Room export** — Export full room transcript as Markdown or JSON
- [ ] **Debate / critique mode** — Structured mode where two agents argue opposing sides of a topic and a judge agent scores them

## Infrastructure & DevOps
- [ ] **Redis integration** — Cache model lists, rate-limit counters, and active stream state
- [ ] **Rate limiting** — Per-user API rate limits (requests/tokens per minute/day)
- [ ] **Background task queue** — Celery or arq for memory extraction, embedding, scheduled actions
- [ ] **Audit logging** — Log all admin actions and sensitive user actions
- [ ] **Multi-tenancy / workspaces** — Group users under organizations with shared knowledge bases and settings
- [ ] **Docker production compose** — Full production stack with Nginx, SSL, and health checks
- [ ] **CI pipeline** — GitHub Actions running lint, tests, and build on every PR
