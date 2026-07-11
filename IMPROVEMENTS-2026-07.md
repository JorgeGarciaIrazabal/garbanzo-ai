# Garbanzo AI — Improvement Backlog (July 2026)

*A fresh research pass over the current codebase (post `bd16312`, the MessageComposer/ReadingColumn refactor and room chat redesign), covering style, UX, UI, architecture, simplicity, and maintainability. Every finding below was verified against the source on 2026-07-11 — items from `APP_REVIEW.md` (June) that were since fixed are **not** repeated here; items carried over are marked ↩︎.*

**How to use:** tasks are checkboxes grouped by theme, each with the issue, the fix, the files involved, and an effort tag (XS / S / M / L). The task-runner skills can consume this file the same way they consume `TASKS.md`.

---

## Executive summary

The app is in notably better shape than at the June review: token counting, streaming performance, memory ranking, RAG thresholds, tool progress, auto-titling, and the settings-drawer split all shipped. The gaps that remain cluster into four themes:

1. **The rooms feature didn't get the chat feature's polish.** Everything hard-won in 1:1 chat — throttled streaming updates, smart auto-scroll, reconnect handling, undo, error UX — is missing from the rooms path, which still rebuilds the whole message list on every WebSocket chunk and yanks the scroll position on every build.
2. **Navigation is not an architecture.** There are no routes: `AuthGate` swaps widgets and everything else is `MaterialPageRoute` pushes. On web this means no deep links, no browser back/refresh support, and no shareable URLs — a real cost for a web-deployed app.
3. **Consistency debt is accumulating quietly.** `deprecated_member_use` is globally ignored (masking 9 files of `withOpacity` and deprecated `DragTarget` callbacks), two import styles coexist (70 relative vs 15 package), the default model `"llama3.2"` is hardcoded in 10+ places, and the same provider error boilerplate is copy-pasted across 13 providers.
4. **The app still looks like a Flutter template.** Stock Material 3 purple seed, duplicated light/dark theme blocks in `main.dart`, no typography choices, generic empty-state icons. Identity is the cheapest remaining "wow" lever.

Top 10 by value-for-effort:

| # | Task | Theme | Effort |
|---|------|-------|--------|
| 1 | Room streaming: throttled per-message updates (port the chat fix) | UX/Perf | M |
| 2 | Room socket reconnect with backoff + "reconnecting…" banner ↩︎ | UX | M |
| 3 | Room smart auto-scroll (port from chat page) | UX | S |
| 4 | URL routing + web deep links (`go_router`) | Architecture | M |
| 5 | App identity: theme extraction, brand palette, typography ↩︎ | UI | M |
| 6 | Stop ignoring `deprecated_member_use`; migrate `withOpacity` → `withValues` | Style | S |
| 7 | Centralize the default model (backend setting + `/models` metadata) | Simplicity | S |
| 8 | Provider error-handling mixin (kills ~15 copies of the same block) ↩︎ | Maintainability | S |
| 9 | CI pipeline (lint + test on push) ↩︎ | Infra | S |
| 10 | Accessibility pass: semantics, contrast, focus ↩︎ | UX | M |

---

## 1. Rooms: bring the chat-page quality to multi-agent chat

The room chat UI was redesigned recently, but the *engineering* underneath still has the problems the 1:1 chat path solved in June. These tasks are the highest-impact block in this document because they compound: rooms are the app's most distinctive feature and currently its least polished.

- [x] **[Frontend] Throttled room streaming updates** — `RoomProvider._onSocketEvent` calls `notifyListeners()` on every `chunk`/`thinking` WS event and rebuilds the entire `ListView` (`room_provider.dart:150–181`, `room_chat_page.dart:84`). This is exactly the "rebuild storm" fixed in `ChatProvider` with a throttled `ValueNotifier` (~12 pushes/s) in June. Port the same pattern: a per-streaming-message `ValueNotifier<RoomMessage?>` + `ValueListenableBuilder` around the live bubble, with `notifyListeners()` reserved for structural events (message added, stream start/end, presence). *(M)*
- [x] **[Frontend] Room smart auto-scroll** — `_RoomChatPageBodyState._autoScroll()` runs on *every build* and always animates to the bottom (`room_chat_page.dart:44–53, 63`), yanking the user away from scrollback whenever any event lands (including presence changes). Port the chat page's near-bottom-gated follow + "jump to bottom" pill (`chat_page.dart:93–146, 194–218`). Consider extracting the logic into a shared `SmartAutoScroll` mixin/helper used by both pages instead of copying it a second time. *(S)*
- [x] **[Frontend] Room socket reconnect + connection state UI** ↩︎ — `RoomSocketService` still has no reconnect path: `onDone` just closes the stream controller and `onError` forwards the error (`room_socket_service.dart:48–54`); `RoomProvider` never learns the socket died, so the user keeps typing into a dead room. Add: exponential-backoff reconnect (with a capped retry count), a `connectionState` exposed to the provider, a slim "Reconnecting…" banner in the room page, and message re-fetch on reconnect to fill the gap. Add a widget/unit test for the reconnect path. *(M)*
- [x] **[Frontend+Backend] Finish or remove the typing indicator** *(finished: wired + rendered)* — the backend broadcasts `{"type":"typing", …}` (`rooms_ws.py:118–122`) and `RoomSocketService.typing()` exists (`room_socket_service.dart:63–65`), but no UI ever *calls* it and no UI *renders* incoming typing events — it's dead wiring on both ends. Either: wire the composer's text changes → debounced `typing(true/false)` and render an "X is typing…" strip above the composer, or delete the event from both sides. Half-built features are the worst maintenance state. *(S)*
- [x] **[Frontend] Destructive room actions need confirmation** — removing a member (`room_chat_page.dart:306–309`) and deleting an agent (`330–334`) fire immediately from an icon tap with no confirm dialog and no undo. Same standard as conversation delete: a confirmation naming the entity, or an undo snackbar. *(XS)*
- [x] **[Frontend+Backend] Room member display names** — the members panel renders raw emails as `title` (`room_chat_page.dart:302`). The backend `User` model has `full_name`; surface it through the room members payload and show name + email subtitle. *(S)*

## 2. Architecture — Frontend

- [x] **[Frontend] Real routing with web deep links** *(go_router + path URLs; AuthGate → AuthState + redirect guard; user-scoped providers moved to an epoch-keyed app-level MultiProvider so logout resets them; chat URL ↔ provider two-way sync)* — the app has zero named routes: `AuthGate` swaps Login/Register/ChatPage by `setState` (`main.dart:103–185`) and rooms/settings/memory/etc. are 11 ad-hoc `MaterialPageRoute` pushes. On Flutter web this means refresh loses your place, no URL for a room or conversation, and browser back is erratic. Adopt `go_router` (or `onGenerateRoute` if minimal): `/login`, `/chat/:conversationId?`, `/rooms/:roomId?`, `/settings`, `/memory`, `/kb`, `/usage`, `/admin`, with an auth redirect guard replacing `AuthGate`. This also naturally fixes "Rooms are invisible on mobile" (APP_REVIEW §3.5) since destinations become linkable. *(M–L)*
- [x] **[Frontend] Shared provider error/loading mixin** ↩︎ *(GuardedStateMixin; admin_provider kept dual channels but shares describeFailure)* — 13 `ChangeNotifier` providers carry 15 hand-rolled `String? _error` fields and ~30 copies of `catch (e) { _error = '…: $e'; if (kDebugMode) print(_error); notifyListeners(); }`. Extract a `ProviderStateMixin` with `error`, `isLoading`, `runGuarded(label, fn)` and typed failure mapping (network vs 401 vs server), then migrate providers incrementally. This is also the place to standardize *user-facing* error copy instead of `'Failed to X: DioException…'` leaking raw exceptions into banners. *(S for the mixin, S–M per provider)*
- [x] **[Frontend] Decouple ModelProvider ↔ ChatProvider with ProxyProvider** ↩︎ — still open from `improvement.md`: `ChatPage` wires `ChatProvider(selectedModelId: () => modelProvider.selectedModelId)` through a manual callback captured at build time (`chat_page.dart:49–56`). Use `ChangeNotifierProxyProvider` so model changes flow through the tree without the closure indirection. *(S)*
- [x] **[Frontend] Provide MemoryProvider / KnowledgeBaseProvider via the tree** ↩︎ *(done with the routing task — both app-level now; SettingsPage/NotificationBell also stopped re-creating their own provider copies)* — both pages still instantiate providers inside `State` (`memory_page.dart:22`, `knowledge_base_page.dart:24`), bypassing the tree. The KB page's polling timer can outlive navigation. Provide them at the route level (natural once routing lands — do together with the routing task). *(S)*
- [ ] **[Frontend] Split the two remaining god files** ↩︎ (reduced scope from June — the settings drawer was already split):
  - `chat_provider.dart` (895 lines): extract conversation CRUD + undo-delete into a `ConversationListController`, leaving `ChatProvider` owning streaming + messages. *(M)*
  - `chat_page.dart` (845 lines): extract the drag-drop/file-validation block (`_handleDroppedFiles`, `_inferMime`, `_formatFileSize`, lines 257–358) into a shared helper — note this logic near-duplicates the validation in the input-widget/file-picker path, so extraction removes a real fork, not just lines. Extract `_PanelResizeHandle` and the app bar too. *(M)*
- [x] **[Frontend] One import style** — 70 files use relative imports, 15 use `package:garbanzo_ai/…` (the newer rooms/composer code). Pick one (package imports are the safer default — they survive file moves better), add the `always_use_package_imports` lint, and fix mechanically. *(S)*

## 3. Architecture — Backend

- [x] **[Backend] Move provider registration to app lifespan** ↩︎ — still open from `improvement.md`: `ChatService.__init__` calls `_ensure_default_provider()` on every instantiation (`chat_service.py:269, 284–287`); registration belongs in `main.py`'s lifespan next to the other startup steps. Delete the per-request check. *(XS)*
- [x] **[Backend] Extract `services/document_parser.py`** ↩︎ — still open: PDF/CSV/spreadsheet/plain-text extraction (`chat_service.py:134–197`) plus the mime-dispatch block inside `send_message` (`:421–453`) live in the chat service. Move to a `document_parser.py` with a single `extract_attachment_text(att) -> str` entry point; unit-test it directly. Shrinks `chat_service.py` (1099 lines) by ~130 and gives KB uploads a shared parser if they ever accept PDFs. *(S)*
- [x] **[Backend+Frontend] Single source of truth for the default model** — `"llama3.2"` is hardcoded in 10+ sites across both stacks (`conversation_service.py:80`, `models/conversation.py:28`, `scheduled_action_job.py:44`, `extract_memories_job.py:12`, `memory_extraction.py:118/194/254`, `schemas/chat.py:197`, plus 4 frontend files including the fallback chain in `model_provider.dart:71`). Add `DEFAULT_MODEL` to `Settings`, thread it through the backend, and expose it via `GET /chat/models` (e.g. a `default_model` field) so the frontend stops guessing with its own hardcoded fallback chain. *(S)*
- [x] **[Backend] Micro-app workspace hardening (small fixes, one task)** — three small issues in `microapp_workspace.py`: (1) `_start_opencode` picks `random.randint(40000, 60000)` with no collision check — bind-test the port or retry on failure (`:308`); (2) `status()` documents "no side effects" but calls `_get_or_create_state`, which mutates `_workspaces` (`:387–390`) — split out a read-only peek; (3) `ensure_sync` can block a worker thread ~60s polling opencode readiness with no per-user guard, so two concurrent `ensure()` calls for the same user race (double-spawn). Add a per-slug lock. *(S)*
- [x] **[Backend] Room WS event schema as typed models** — `rooms_ws.py` and `room_chat_service.py` build event dicts inline (`{"type": "chunk", …}`) and the Flutter side string-matches `type` (including a `thinking_chunk` legacy alias kept for compatibility, `room_provider.dart:165`). Define the event types once in `schemas/room.py` (Pydantic, with a `Literal` type field), emit only canonical names, and drop the legacy alias after one deploy. Prevents schema drift on the app's only realtime protocol. *(S)*

## 4. Style & consistency

- [x] **[Frontend] Stop suppressing deprecation warnings** — `analysis_options.yaml` sets `deprecated_member_use: ignore`, which is why `flutter analyze` is "clean" while 9 files still use `withOpacity` (vs 22 on `withValues`) and `chat_page.dart` uses the deprecated `DragTarget.onWillAccept`/`onAccept`/`onLeave` trio (`:373–381`). Remove the ignore, migrate the hits, and let future deprecations surface at lint time instead of at the next SDK upgrade. *(S)*
- [x] **[Frontend] Tighten the lint set** — the project runs bare `flutter_lints` with zero custom rules. Given the codebase's conventions are actually good, encode them: `always_use_package_imports` (see §2), `prefer_final_locals`, `unawaited_futures`. And the `if (kDebugMode) print(...)` pattern (~30 sites) should become a tiny `logDebug()` util or `dart:developer log()` — greppable, one-line switch to real logging later. *(S)*
- [x] **[Repo] Root hygiene** — `flutter_01.log` sits untracked at the repo root, and `improvement.md` is ~80% superseded by `APP_REVIEW.md` (which says so itself). Add `flutter_*.log` to `.gitignore`, delete the stray log, and either delete `improvement.md` or reduce it to a pointer at `APP_REVIEW.md` + this file. Three overlapping review documents is two too many; a newcomer can't tell which one is live. *(XS)*
- [x] **[Backend] Expand ruff a notch** — current select is `E,F,I,N,W,UP`. Add `B` (bugbear — mutable default args, useless comprehensions), `SIM` (simplify), and `ASYNC` (blocking calls in async contexts — directly relevant given how much of this backend is async with `to_thread` escapes). Fix what surfaces; the codebase is clean enough that this should be a small diff. *(S)*

## 5. UX

- [ ] **[Frontend] Accessibility pass** ↩︎ — still essentially unstarted: exactly **1** `Semantics`/`semanticLabel` usage in the entire `lib/` tree. The June review's message-action tooltips shipped (tooltips give labels for free), but: icon-only buttons elsewhere (composer, room actions, sidebar), missing focus outlines on text fields, and the `onSurfaceVariant`-at-low-alpha contrast issue remain. Concrete pass: (1) every `IconButton` gets a `tooltip:`; (2) images/avatars get `semanticLabel`; (3) run the app with TalkBack/Orca once and fix what's unreadable; (4) verify AA contrast on secondary text in both themes. *(M)*
- [x] **[Frontend] Humanize auth errors** ↩︎ — `login_page.dart:58–64` still collapses every non-401 failure into "An unexpected error occurred." Distinguish: bad credentials / server unreachable (connection refused) / network down (DNS, socket) — the `ProviderStateMixin` failure mapping from §2 gives this for free if built first. *(XS after §2)*
- [ ] **[Frontend] Mermaid rendering on web** ↩︎ — still open from `improvement.md`: `mermaid_diagram.dart:55, 288` falls back to a plain code block when `kIsWeb`. The plan stands: load `mermaid.js` from `web/index.html` (vendored, not CDN, so it works offline), render via `dart:js_interop` + `HtmlElementView`, keep the code-block fallback on render errors. *(M)*
- [ ] **[Frontend] Conversation search on mobile** ↩︎ — search is still desktop-sidebar-only; mobile gets no entry point. Add a search icon to the mobile app bar routing to the same `SearchProvider` flow. *(S)*
- [ ] **[Frontend] Micro-app panel discoverability** — the panel opens automatically from tool results or via the composer button, but on narrow screens it takes over full-screen (`chat_page.dart:501–507`) with `showCloseAsBack` as the only affordance, and once closed there's no way to re-open it without re-triggering the tool. Track "panel was open for this conversation" and offer a re-open chip in the app bar. *(S)*
- [ ] **[Frontend] Loading-state consistency** ↩︎ — partially addressed since June but still mixed: bare `CircularProgressIndicator` centers in some pages, text in others, nothing during room open. Standardize: skeleton rows for list pages (conversations, rooms, memories, KB docs), inline spinners for actions. Build 1–2 shared skeleton widgets first. *(M)*

## 6. UI / visual identity

- [x] **[Frontend] Extract and de-duplicate the theme** — `main.dart:33–82` defines light and dark themes as two near-identical 25-line blocks differing only in `brightness`. Extract `core/theme.dart` with a single `buildTheme(Brightness)` and put *all* shared component theming there (card shape, input borders, app bar) so pages stop re-styling locally. Prerequisite for the identity task below. *(XS)*
- [ ] **[Frontend] Give the app an identity** ↩︎ — still the stock M3 purple seed (`Color(0xFF6750A4)` — literally the Material default). This is the "premium aesthetic" item from `improvement.md`, scoped concretely: (1) pick a garbanzo-appropriate palette (warm chickpea/olive/cream tones are an obvious, distinctive direction) and set it as the seed; (2) choose one typeface pairing (e.g. Inter body + Outfit headings, bundled locally — no runtime font fetch) and set it in the extracted theme; (3) replace the generic `Icons.forum_outlined`-style empty-state icons with one small custom illustration or mascot used consistently (empty chat, empty room, empty KB, empty notifications). Skip glassmorphism/gradients until these land — palette + type is 80% of the effect. *(M)*
- [ ] **[Frontend] Micro-animations** ↩︎ — carried from `improvement.md`, still absent: message-appear fade/slide, animated thinking indicator, dialog/drawer transitions. Do *after* the theme work so animation curves/durations get defined once alongside it. *(M)*
- [ ] **[Frontend] Room message visual parity check** — the room redesign introduced `RoomMessageBubble` (490 lines) separate from `ChatMessageWidget`; verify markdown rendering there goes through the same memoized `MarkdownWidget` path and that agent thinking blocks, code blocks, and copy actions behave identically to 1:1 chat. Divergence here will read as jank to users who use both. *(S, mostly verification)*

## 7. Infrastructure & delivery

- [x] **[Infra] CI pipeline** ↩︎ *(workflow created; will be validated by the first push)* — there is still no `.github/workflows/`. Minimum viable: one workflow running `just be-lint && just be-test` (Python 3.12 + uv; postgres service container for the pgvector tests) and `just fe-lint && just fe-test` (Flutter stable) on push/PR to main. The justfile already encodes everything, so this is mostly YAML plumbing. Add a badge to README. *(S)*
- [ ] **[Backend] Rate limiting on expensive endpoints** ↩︎ — still open and still worth it pre-multi-user: `slowapi` (or a 30-line token-bucket dependency) on `/chat/**/chat`, `/tts/*`, `/stt/*`, keyed by user. Config-driven limits so dev stays unlimited. *(S–M)*
- [x] **[Backend] Startup config validation** — `SECRET_KEY` is required but nothing validates it isn't a placeholder in prod; `MICROAPPS_*`, `FIREBASE_*`, and ngrok settings fail at first use rather than at boot. Add a lifespan check that logs a clear table of enabled/disabled features and hard-fails on placeholder secrets when `debug=False`. *(S)*
- [ ] **[Deferred, recorded for completeness]** Redis broker / task queue / Alembic / multi-tenancy — the June assessment stands: not needed at current scale; revisit if the backend goes multi-process. Feature-backlog items (folders/tags, reactions, conversation export, debate mode, cloud LLM provider) remain tracked in `TASKS.md` and `APP_REVIEW.md §6` — not duplicated here.

## 8. Tests worth adding (targeted, not coverage-chasing)

- [x] **[Test] Room socket reconnect + room provider stream lifecycle** — pairs with §1; `test/` currently has **zero** rooms coverage on the frontend (the backend has plenty). *(bundle with the §1 tasks)*
- [x] **[Test] `document_parser` unit tests** — with §3's extraction: PDF happy path, corrupt base64, oversized CSV truncation, multi-sheet spreadsheet. *(bundle with the §3 task)*
- [x] **[Test] Typed room WS events** — schema round-trip once §3's event models land. *(bundle with the §3 task)*
- [ ] **[Test] E2E smoke for rooms** — the `/e2e-testing` skill covers 1:1 chat; add one room flow (create room → add agent → @mention → streamed reply renders). *(M)*

---

## Suggested sequencing

**Wave 1 — consistency floor (a few days):** §4 all four tasks + §3 lifespan / document-parser / default-model + §2 error mixin. Small, independent, and everything after gets cheaper.

**Wave 2 — rooms parity (≈1 week):** §1 in order (streaming throttle → auto-scroll → reconnect → typing → confirmations → display names). Highest user-visible payoff in the document.

**Wave 3 — structure (≈1 week):** §2 routing + tree-provided providers + god-file splits (routing first; the splits get easier once pages own routes).

**Wave 4 — look & feel (≈1 week):** §6 theme extraction → identity → micro-animations, then §5 accessibility and the remaining UX items.

**Continuous:** §7 CI lands in wave 1 (it protects every later wave); rate limiting and config validation whenever convenient.
