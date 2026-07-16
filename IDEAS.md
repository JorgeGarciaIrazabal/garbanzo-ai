# Ideas — Expanded Backlog

Difficulty legend (pick the model per task, not per feature):

| Tag | Meaning | Suggested model |
|-----|---------|-----------------|
| `easy` | Mechanical, well-trodden pattern in this repo, low ambiguity | Haiku / small model |
| `easy-med` | Mostly mechanical but touches 2+ layers or needs a migration | Sonnet |
| `medium` | New endpoint/widget with some design decisions, single feature area | Opus |
| `med-hard` | Cross-cutting, stateful UI, or careful prompt/tool design | Fable |
| `hard` | Novel UX, tricky Flutter internals, multi-step agentic behavior | Fable |

Work task by task in order, use subagent with right model to execute on each of the subtasks and commit/push after each task is completed

---

## 1. AI-assisted system prompt creation

Add a "✨ Create with AI" flow to the existing system prompt editor. The user describes what they want ("a sarcastic coding mentor that keeps answers short") and the LLM drafts a well-structured prompt; the user can then iterate ("make it friendlier") before saving. Reuses `SystemPromptTemplate` + `SystemPromptEditorDialog` — no new storage needed.

- [x] `easy-med` **Backend: generate endpoint** — `POST /api/v1/system-prompts/generate` taking `{intent, existing_prompt?, feedback?}`; calls the LLM with a meta-prompt that outputs only the prompt text. Support the same SSE streaming shape as chat so the draft streams into the editor.
- [x] `easy` **Meta-prompt engineering** — Write and test the meta-prompt: produce prompts with persona, tone, constraints, and output-format sections; when `existing_prompt` + `feedback` are given, revise instead of regenerate.
- [x] `medium` **Frontend: AI flow in SystemPromptEditorDialog** — "Create with AI" button → intent text field → streamed draft preview → Accept / Refine (feedback field) / Discard. Refine loops back to the endpoint with the current draft.
- [x] `easy` **Rate-limit + model choice** — Route generation through the user's currently selected model; apply the existing `rate_limit.py` throttling.

## 2. "Styles" — unified model / thinking / prompt selector

Replace the plain model dropdown with a **Style** concept: a style = model + thinking level + system prompt (+ optionally voice). Users can compose one ad-hoc per conversation or save named styles ("Deep Work", "Quick Answers", "Funny Friend"). This is the flagship UX item — worth a design pass before coding.

- [x] `easy-med` **Backend: thinking level on conversations** — Add `thinking_level` (`off | low | medium | high`) to `Conversation` + migration + schema; pass through `chat_service` → `ollama_provider` (`think` option). Detect/flag per-model support so the UI can grey it out.
- [x] `easy-med` **Backend: saved styles** — New `Style` model (name, model_id, thinking_level, system_prompt_template_id, is_default) + CRUD endpoints. Alternatively extend `SystemPromptTemplate` with model/thinking columns — decide during planning; a separate table is cleaner.
- [ ] `med-hard` **Frontend: Style picker UI** — Redesign `ModelSelectorWidget` into a popover/bottom-sheet: saved styles as cards at top, then expandable "Customize" with model list (search + capability badges: vision/tools/thinking), thinking-level segmented control, and prompt template picker. Must feel great on both desktop and mobile — do a `frontend-design` pass first.
- [ ] `easy` **Frontend: style chip in the app bar** — Show the active style name/emoji next to the conversation title; tap to open the picker. Persist last-used style for new conversations.
- [ ] `medium` **Model capability metadata** — Extend `AvailableModel` / `GET /chat/models` with capability flags (supports_thinking, supports_tools, supports_vision) populated by the admin sync so the picker can badge and filter.

## 3. Dynamic context: location + timestamp

Inject a compact, clearly-scoped context block (current datetime, timezone, coarse location) into the system prompt on every request so answers about "today", "near me", "this weekend" just work — with wording that tells the model to use it only when relevant.

- [ ] `easy` **Backend: context block injection** — In `chat_context.py`, append a `<context>` block with server-side UTC time + user's local time/timezone. Frame it as "background info; only use when relevant to the request".
- [ ] `easy` **Frontend: send timezone** — Include IANA timezone (and locale) in the chat request or persist on the `User` at login. Timezone needs no permission prompt.
- [ ] `easy-med` **Frontend: optional location** — Settings toggle (default off) to share coarse location: city-level via `geolocator` + reverse-geocode once, cached; never raw coordinates in the prompt. Handle web/desktop/Android permission differences.
- [ ] `easy` **Rooms parity** — Inject the same context block in `agent_turn.py` so room agents also know the time.
- [ ] `easy` **Tests** — Backend test asserting the block is present, correctly formatted, and absent when the user disabled location.

## 4. Native "app help" skill (and later, in-app actions)

The assistant should answer "how do I pin a conversation?" from curated app docs, via the existing native-tools mechanism (`native_tools.py`) rather than an MCP server. Second iteration: let it *do* things ("create a room with Ana and a research agent") with a confirmation step.

**Iteration 1 — explain:**
- [ ] `easy` (laborious) **Write the app user guide** — One markdown file per feature area (chat, rooms, memories, KB, styles, notifications, scheduled actions, talk mode…) in `backend/app/docs/` or similar. Short, task-oriented, "how do I X" phrasing. Good bulk task for a cheap model + human skim.
- [ ] `medium` **Native tool `app_help(query)`** — Add to `native_tools.py`: embed the docs with the existing `embedding_provider` (or plain keyword scoring to start — decide by testing quality), return top chunks. Docs are static, so embed once at startup and cache in memory; no DB tables needed.
- [ ] `easy` **Prompt nudge** — Mention in the base system prompt that an app-help tool exists, so models actually call it when asked about the app.
- [ ] `easy` **Keep docs honest** — Add a line to CLAUDE.md: when a user-facing feature changes, update its help doc in the same PR.

**Iteration 2 — act:**
- [ ] `med-hard` **Action tools design** — Define a small, safe set of native tools: `create_room(name, member_emails, agents)`, `create_scheduled_action(...)` (exists), `save_memory(...)` (exists), `set_conversation_style(...)`. Each returns a structured "proposal" rather than executing directly.
- [ ] `med-hard` **Confirmation UX** — New SSE chunk type (`action_proposal`) rendered as a card in `ChatMessageWidget` with Confirm/Cancel; on confirm the frontend calls the real REST endpoint it already knows. Keeps the LLM out of the execution path and reuses existing auth.
- [ ] `medium` **Deep links after action** — Confirmed action responses include a route (`/rooms/{id}`) the frontend can offer to navigate to.

## 5. Friends

A lightweight social graph so rooms stop requiring raw email entry. Friend requests by email, accept/decline, and a friends list that powers autocompletion everywhere (idea 6) and future sharing features.

- [ ] `medium` **Backend: Friendship model + endpoints** — `Friendship(requester_email, addressee_email, status: pending|accepted|blocked, created_at)` + migration. Endpoints: `POST /friends/requests`, `POST /friends/requests/{id}/accept|decline`, `GET /friends`, `DELETE /friends/{email}`, `GET /friends/search?q=` (only among accepted friends).
- [ ] `easy-med` **Notifications integration** — Friend request / accepted events through the existing `notification_service` + FCM, with a new `NotificationPreferences` category.
- [ ] `medium` **Frontend: Friends page** — List with pending (incoming/outgoing) and accepted sections; add-by-email field; accept/decline/remove actions. New `FriendsProvider` + service following the existing feature-folder pattern.
- [ ] `easy-med` **Rooms: add members from friends** — In `CreateRoomDialog` and member management, replace the raw email field with a friend picker (search + chips). Keep a "by email" fallback for non-friends.
- [ ] `easy` **Privacy guard** — Searching users by email only confirms existence on exact match (no enumeration); block list respected everywhere.

## 6. Mention autocompletion (@friends, @agents, /skills, #tools)

Typing `@` in a room suggests friends and agents; `/` in chat suggests skills/prompt templates; `#` (or `@tool`) suggests enabled MCP + native tools. The hard part is a good reusable Flutter overlay — build it once, wire it everywhere.

- [ ] `easy` **Backend: suggestion sources** — Everything mostly exists (`GET /mcp/tools`, room agents, templates, friends from idea 5). Add one thin `GET /autocomplete?context=room|chat&q=` endpoint or just fetch-and-filter client-side — client-side is simpler and the lists are small; start there.
- [ ] `hard` **Frontend: mention overlay engine** — Reusable `MentionTextController` + overlay widget: detects trigger chars at the cursor, filters candidates as you type, keyboard navigation (↑↓⏎/Esc) on desktop, tap on mobile, inserts a styled token/text. This is the genuinely tricky Flutter work (cursor geometry, IME, web quirks) — give it your best model and a focused session.
- [ ] `medium` **Wire into RoomComposeBar** — `@` → members + agents. Render mentions highlighted in `RoomMessageBubble`.
- [ ] `medium` **Wire into ChatInputWidget** — `/` → prompt templates & app actions; `#` → tools (inserting a tool mention nudges the model to use it via a hint appended to the request).
- [ ] `medium` **Backend: @agent targeting in rooms** — When a room message mentions a specific agent, route the turn to that agent directly, bypassing the auto-judge (`ROOM_AUTO_JUDGE_MODEL`) only for that message.

## 7. Room notification muting

WhatsApp-style: mute a room for 8 hours, 1 week, or forever. Per-member setting, checked at send time.

- [x] `easy` **Backend: `muted_until` on RoomMember** — Nullable timestamp (far-future sentinel or separate `muted_forever` bool) + `ADD COLUMN IF NOT EXISTS` migration + `PATCH /rooms/{id}/members/me/mute` endpoint.
- [x] `easy` **Backend: respect mute** — In `notification_service` / room FCM path, skip push + in-app notification when muted (messages still appear in the room; unread badge choice: keep counting, like WhatsApp).
- [x] `easy-med` **Frontend: mute UI** — Bell icon in room header + long-press/context-menu on the room list entry → sheet with 8 hours / 1 week / Always options and "Unmute". Show a muted-bell glyph on muted rooms in the sidebar.
- [x] `easy` **Auto-expiry** — No job needed: compare `muted_until` to `now()` at notification time.

---

## Proposed additions (not in the original list)

- [ ] `easy-med` **8. Conversation-level mute / focus** — Same mute mechanism for the disconnect-mid-stream FCM pushes on regular conversations; cheap once idea 7 lands. *(Do first with 7 — smallest full-stack slice, good warm-up.)*
- [ ] `medium` **9. Shared styles/prompts with friends** — Once friends (5) and styles (2) exist, let users share a style or prompt template to a friend (copy-on-accept, no live sync). Natural glue between two features.
- [ ] `med-hard` **10. Room unread counts + read receipts** — `last_read_message_id` per RoomMember, unread badges in the sidebar, optional "seen" indicators. Pairs with muting to make rooms feel like a real messenger.
- [ ] `medium` **11. Onboarding tour powered by the help docs** — First-login checklist/coach-marks generated from the same app-guide docs as idea 4, so there's one source of truth for "how the app works".
- [ ] `easy` **12. `/help` command in chat** — Before idea 4's tool exists, a client-side `/help <question>` that stuffs the relevant doc into context — a one-day version to validate the docs are good.


## 13. Configurable, auto-detecting STT/TTS language

Let users pick which languages they speak (e.g. English + Spanish) or leave it on **Auto**, and have Talk Mode follow along — detecting the spoken language per turn and replying in kind, with a manual override available mid-conversation. Today `STTService` (`backend/app/services/stt_service.py`) always forces a single language from `settings.stt_language`, so faster-whisper's built-in auto-detect (triggered by passing `language=None`) is never actually used; Kokoro TTS (`tts_service.py`) only ships English voices (`_VOICES`), with the reply language implicitly fixed by whichever voice ID is configured.

- [ ] `easy-med` **Backend: STT auto-detect + per-request language** — Add an optional `language` field (ISO code or `"auto"`) to `POST /transcribe`; when `"auto"`/omitted, call `WhisperModel.transcribe(language=None, ...)` instead of always injecting `settings.stt_language`, and surface the detected code via the existing `TranscriptionResponse.language` field. Thread the same optional param through `RemoteSTTService`.
- [ ] `easy` **Backend/frontend: multi-language preference** — Add a `preferred_languages` list (e.g. `["en", "es"]`) + `auto` toggle, following the pattern of today's `ttsVoice`/`ttsSpeed` settings in `SettingsProvider` (`lib/features/settings/providers/settings_provider.dart`), which currently live only in `SharedPreferences`. Decide whether this needs a `User` column to sync cross-device or can stay local-only like the existing TTS prefs.
- [ ] `medium` **TTS: non-English voices** — `tts_service.py` already derives Kokoro's `lang_code` from the voice ID's first letter; add Kokoro's other language packs to `_VOICES` with a correct `language` field, and auto-pick the voice from the detected/preferred language instead of the hardcoded default when the user hasn't pinned one.
- [ ] `med-hard` **Talk Mode: language follows the conversation** — In `TalkModeController`/`talk_mode_page.dart` (currently language-agnostic), when STT reports a detected language different from the active TTS voice's language and the user is in Auto mode, switch the reply voice to match (bounded to `preferred_languages`); add a small in-call control to override the language manually without leaving the call.
- [ ] `easy` **Settings UI** — Language multi-select + Auto toggle alongside the existing voice/speed controls.

## 14. In-app bug/feature submission (admin-visible)

Let users submit bug reports or feature requests from inside the app; admins triage them from a new admin page, following the same admin-managed pattern as `MCPServer`/`AvailableModel` today. No existing model fits directly — `ScheduledAction` (`backend/app/models/scheduled_action.py`) is the closest structural template (simple user-owned table keyed off `user_id → users.email`, with a matching endpoint/service/schema split).

- [ ] `easy-med` **Backend: Report model + endpoints** — New `Report` model (`id`, `user_id` FK `users.email` CASCADE, `type: bug|feature`, `title`, `description`, `status: open|in_progress|closed`, `created_at`/`updated_at`) + `NNN_add_reports_table.sql` migration. Endpoints: `POST /reports` + `GET /reports/mine` for any authed user; `GET /admin/reports` + `PATCH /admin/reports/{id}` gated by the existing `get_current_admin_user` dependency used throughout `admin.py`.
- [ ] `easy` **Docs** — Add the new endpoints to `docs/api.md` and the model to `docs/database.md` in the same commit, per the root `CLAUDE.md` doc-maintenance rule.
- [ ] `medium` **Frontend: submission form** — Type toggle (bug/feature) + title + description, reachable from the Settings drawer alongside `pages_section.dart`/`profile_section.dart`.
- [ ] `medium` **Frontend: admin triage view** — New admin page listing reports with status filter/update, alongside the existing Users/MCP Servers/Models admin pages, gated the same way (`AuthService.instance.cachedUser?.isAdmin`).
- [ ] `easy-med` **Notifications (optional)** — Notify admins via the existing `notification_service` when a new report lands.

## 15. Talk/call button in the text input bar

ChatGPT puts its voice-call entry point right in the composer; this app currently only exposes Talk Mode via a button in the chat app bar (`chat_app_bar.dart`, `ValueKey('talk_mode_button')`, `Icons.graphic_eq`), separate from the composer's own dictation mic (`ValueKey('voice_button')` in `lib/features/chat/widgets/input/message_composer.dart`, wired to `VoiceRecordingHelper` for inline speech-to-text). Move/add the call entry point into the composer so it's discoverable right where the user is typing.

- [ ] `easy` **Frontend: add call button to `MessageComposer`** — Add a button beside the existing dictation mic that opens `TalkModePage.open(...)` (same call currently wired from `chat_app_bar.dart`), disabled while sending, matching today's guard.
- [ ] `easy` **Resolve the app-bar duplicate** — Decide whether to remove the existing `chat_app_bar.dart` talk button once it's in the composer, or keep both for different layout widths.
- [ ] `medium` **UI/UX pass** — Icon and placement so it doesn't collide with the dictation mic and send button; consider a call-style icon (`Icons.call`/waveform) vs. today's `Icons.graphic_eq`, and how it collapses on narrow/mobile vs. desktop widths. Good candidate for a `frontend-design` pass given the explicit "good UI/UX" ask.
- [ ] `easy` **Rooms parity (out of scope for now)** — Rooms currently have no dedicated compose bar or voice affordance at all; note this as a follow-up rather than solving it here.