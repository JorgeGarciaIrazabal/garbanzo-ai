# Garbanzo AI — Full Application Review

*A deep review of the entire app — backend, frontend, AI architecture, and human UX — with everything I would change, simplify, or enhance. Findings were produced by four parallel expert reviews (backend engineering, Flutter engineering, AI/LLM architecture, product UX) and the highest-severity claims were verified against the source.*

*Complements (and partially supersedes) the earlier `improvement.md` task list.*

---

## Executive Summary

**Overall verdict: a genuinely solid self-hosted AI app with a clean architecture and several features done better than most open-source equivalents** — real thinking-token streaming, a correct multi-step MCP tool loop, an empirically-validated multi-agent auto-judge, token-refresh coalescing, and disciplined async hygiene (`asyncio.to_thread` for TTS/STT/embeddings).

The three biggest gaps, in order of impact:

1. **The AI core runs on guesses, not measurements.** There is no real token counting anywhere — context limits are inferred from model names, summarization triggers on estimates, and memories/KB chunks are injected with no token budget. Everything downstream (context indicator, summarization quality, memory bloat) inherits this imprecision.
2. **The streaming UX rebuilds the world on every chunk.** Each SSE chunk calls `notifyListeners()` and re-renders the entire message list, with full markdown re-parsing. This is the single largest source of jank and the highest-ROI performance fix in the app.
3. **The app doesn't tell the user what the AI is doing.** No "memories used" indicator, no tool-execution progress, no first-token latency cue, no relevance threshold on RAG injection, raw JSON in tool bubbles. For an app whose differentiator is *personal context* (memory + KB + tools), the user can't see any of it working.

Everything below is grouped by theme, each item with severity and a concrete fix. A phased roadmap is at the end.

---

## 1. The Ten Changes That Matter Most

| # | Change | Why | Effort |
|---|--------|-----|--------|
| 1 | **Real token counting** (`TokenCounter` service, per-model, cached) | Unblocks accurate context budgeting, summarization, memory/KB limits, honest context indicator | M |
| 2 | **Fix the streaming rebuild storm** (per-message `ValueNotifier` + throttled markdown parsing) | Biggest perceived-quality win; chat feels instantly smoother | M |
| 3 | **Memory ranking + token budget** (top-K by relevance/recency, dedup, decay) | Memory currently degrades with use — the more the app learns, the worse the context gets | M |
| 4 | **Tool-execution progress streaming** (`tool_call_start`/`end` chunks + human-readable tool bubbles) | Tools currently feel like the app froze; this is table stakes in 2026 | S–M |
| 5 | **Auto-generate conversation titles** | Cheap, high-delight, expected by every user coming from Claude/ChatGPT | S |
| 6 | **Smart auto-scroll** (only scroll if already near bottom; "↓ New message" pill otherwise) | Fixes the most annoying moment in the core loop: losing your place mid-read | S |
| 7 | **WebSocket auth: reject refresh tokens** (`payload["type"] == "access"` check in `rooms_ws.py`) | Security gap, one-line fix | XS |
| 8 | **RAG relevance threshold + hybrid search** | Low-score chunks currently pollute context silently | M |
| 9 | **Split the two god-files**: `chat_service.py` (~1000 lines) and `settings_drawer.dart` (940 lines) | Every future feature pays a tax on these | M |
| 10 | **"What the AI knows" transparency**: memories-used badge, context breakdown tooltip, KB citation surfacing | Turns the app's hidden strengths into visible trust | M |

---

## 2. AI / LLM Architecture

### 2.1 Token & context management *(weakest area)*

- **HIGH — No real token counting.** Context length is a heuristic on the model name (`chat_service.py:180–195`); budgets are `estimated * 0.8`. Token metadata comes only from Ollama's `eval_count` after the fact.
  *Fix:* a `TokenCounter` service (tokenizer per model family, cached), used for context assembly, summarization triggers, and memory/KB budgets.
- **MEDIUM — Summarization loses tool results.** The rolling summary (`chat_service.py:197–270`) truncates messages to text previews; structured tool outputs vanish. Add tool-result digests to the summary prompt ("Tool `x` returned …").
- **MEDIUM — Summarization prompt is generic and unevaluated.** Add explicit instructions to preserve user preferences, goals, and decisions; test against real long conversations.
- **LOW — `context_summary_until_id` can go stale** after message edits/deletes. Add a validity check when loading.
- ✅ *Done well:* the 80%-trigger + keep-last-10 + persist-boundary design is sound; it just needs real numbers underneath.

### 2.2 Memory system

- **HIGH — All matching memories are injected every turn** with a plain `ilike` substring match (`memory_service.py:76–86`, injected at `chat_service.py:856–866`). No ranking, no token budget, no cap. A power user with 100+ memories pays full freight on every message.
  *Fix:* embed memories (pgvector is already there), rank by semantic relevance + recency, cap at top 5–10 within a token budget.
- **MEDIUM — No deduplication.** Daily extraction will re-learn "user works at Acme" forever. Consolidate near-duplicates via embedding similarity after each extraction run.
- **MEDIUM — No decay/aging.** Add `last_confirmed_at`; down-rank or prompt-to-confirm memories untouched for ~90 days.
- **MEDIUM — Extraction prompt produces verbose facts** (`memory_extraction.py:20–45`). Instruct: one sentence per fact, specific over general, max N per run.
- **LOW — Only a 24h lookback.** Add a weekly pass for longer-arc patterns.

### 2.3 RAG / Knowledge base

- **MEDIUM — No relevance threshold.** Even a 0.1-cosine match gets injected (`chat_service.py:871–890`). Set a floor (~0.5) and a token budget for the KB block.
- **MEDIUM — Embedding-only retrieval.** Exact-keyword queries ("what's the API key format?") can miss. Add BM25/`tsvector` hybrid fusion — Postgres gives you this for free.
- **MEDIUM — No reranking and no document-level grouping.** For long PDFs, near-duplicate chunks from one doc can crowd out better sources. Group by document, optionally rerank top-K with the LLM.
- **MEDIUM — Background embedding can fail silently**, leaving documents stuck in "processing" (`knowledge_base_service.py:199–206`). The task should set `status="failed"` + `error_message` on exception, with a retry path.
- **LOW — Citations are decorative.** The prompt shows filenames but doesn't require the model to cite. Enforce "According to [filename]…" phrasing and render citations as chips in the UI.
- ✅ *Done well:* paragraph/sentence-aware chunking with overlap, batch embedding, per-document status tracking.

### 2.4 Tool use / MCP

- **HIGH — No execution progress UX.** A 10-second tool call shows nothing. Emit `tool_call_start` / `tool_call_end` chunk types so the frontend can render "Running `search_web`… ✓ 2.3s".
- **MEDIUM — Tool errors are opaque to the model** (`{"ok": false, "error": str(exc)}`, `mcp_service.py:254–256`). Categorize (rate_limit / auth / not_found / timeout) with recovery hints so the model can self-correct.
- **MEDIUM — No tool-result size cap.** A tool returning megabytes blows the context. Truncate to a configurable limit (~8KB) with an explicit "truncated" marker.
- ✅ *Done well:* the multi-iteration loop with `pending_thinking` carried across iterations, per-conversation whitelists, tool-name sanitization across servers, short-lived MCP sessions with timeouts.

### 2.5 Provider layer

- **HIGH (strategic) — Ollama-only.** The `LLMProvider` ABC is clean, but no cloud provider exists. Add an Anthropic/OpenAI provider (with API-key config, retries, and cost tracking in `usage_service`) — this single change makes the app dramatically more useful.
- **MEDIUM — No capability flags on `ModelInfo`** (`supports_tools`, `supports_vision`, `supports_thinking`). The UI can't grey out tool toggles for non-tool models; requests just fail.
- **MEDIUM — No per-chunk streaming timeout and no retry.** A wedged Ollama stream hangs forever (`ollama_provider.py:39` sets only a global 300s client timeout); a transient disconnect fails the whole request. Wrap chunk iteration in `asyncio.wait_for` and add bounded retry-with-backoff for connection errors.

### 2.6 Prompts & polish

- **MEDIUM — Generic fallback system prompt** ("You are a helpful AI assistant.", `chat_service.py:896`). Give Garbanzo an identity that references its memory/personalization powers.
- **MEDIUM — No conversation auto-titling** *(verified: none exists)*. After the first exchange, fire a cheap background LLM call for a 3–5 word title. Small effort, large perceived quality.
- **LOW — No follow-up suggestions** after responses — nice-to-have, pairs well with auto-titling using the same cheap-model pathway.

### 2.7 Multi-agent rooms

- **MEDIUM — Auto-judge cost scales linearly with agent count** (one judge LLM call per auto-agent per message, `room_chat_service.py:385–396`). Batch into a single "which of these agents should respond?" call.
- **MEDIUM — Agent self-mention recursion** is only bounded by `max_agent_turn_depth`; exclude an agent's own name from mention-scanning of its output.
- **LOW — Agents are name+prompt only.** `expertise_tags` on `RoomAgent` would improve judge routing and the add-agent UX.
- ✅ *Done well:* mention parsing, round-robin fairness, and the benchmark-validated judge prompt are genuinely good engineering.

---

## 3. User Experience (the human side)

### 3.1 Streaming & the core chat loop

- **HIGH — Auto-scroll fights the reader.** New chunks always jump to bottom (`chat_page.dart:224–225`). Only auto-scroll when already near the bottom; otherwise show a "↓ New message" pill.
- **MEDIUM — No first-token latency cue.** Between send and first chunk there is silence. Show a pulsing "…" placeholder immediately.
- **MEDIUM — Thinking block auto-collapses mid-read** when the answer starts (`thinking_content.dart:32–44`). Collapse with a gentle animation only if the user never expanded it manually.
- **LOW — Stopped responses look identical to finished ones.** Add a small "Stopped" badge to interrupted messages.
- **MEDIUM — Message actions (copy/edit/regenerate/branch/speak) are nearly invisible** — 14px icons in muted colors (`chat_message_widget.dart:183–259`). Reveal on hover (desktop) / long-press menu (mobile), with tooltips.

### 3.2 Trust & transparency *(the biggest missed differentiator)*

The app quietly does sophisticated things — memory injection, RAG, summarization, tool runs — and shows the user none of it:

- **Memories-used badge** on assistant messages ("🧠 3 memories used", tappable to view which).
- **Context indicator needs explanation**: show actual token counts and what happens at 80%+ ("older messages get summarized"), not just a bare percentage bar (`context_window_indicator.dart`).
- **Tool bubbles render raw JSON** (`tool_bubble_widget.dart:70–100`). Render "🔍 search — *query: 'x'* — ✓ done" with expandable details.
- **KB citations as chips** under answers that used the knowledge base.
- **Model info affordance**: name, context window, speed — one tap from the model selector.

### 3.3 Onboarding & empty states

- **MEDIUM — Zero onboarding.** New users land in `EmptyChatState` with three hardcoded generic chips. Add a dismissible "Getting started" card surfacing the differentiators (voice, files, memory, rooms, tools).
- **MEDIUM — Auth errors are generic** ("An unexpected error occurred", `login_page.dart:57–64`). Distinguish bad credentials / server down / network down, and surface backend reachability before the user types.

### 3.4 Voice

- **MEDIUM — No recording timer**; just a pulsing dot. Show elapsed time.
- **MEDIUM — Transcription failures dump raw exceptions** into a snackbar. Map to human messages (too quiet / service down / network).
- **MEDIUM — Silent failure when no audio device exists** (`voice_recording_helper.dart:120–162`): user sees "Recording…" while nothing records. Detect and toast immediately.

### 3.5 Information architecture

- **MEDIUM — The settings drawer is a junk drawer**: 8+ destinations mixed with toggles in one 940-line widget. Split into "Quick settings" (toggles) and "Pages" (Memory, KB, Rooms, Skills, Usage, Admin) sections — and split the widget file accordingly (see §4).
- **MEDIUM — Rooms are invisible on mobile** (buried in the drawer, while desktop gets a sidebar tab). Promote to a tab or first-run hint.
- **LOW — Search is desktop-sidebar-only**; add a search icon to the mobile app bar.
- **LOW — Admin entry shows for everyone**; hide unless `is_admin`.

### 3.6 Safety nets & state consistency

- **MEDIUM — Deleting a conversation has no undo.** Backend already soft-deletes — surface that: "Conversation deleted — Undo" snackbar.
- **HIGH — Audit destructive admin actions** (delete MCP server, disable user) for confirmation dialogs naming the affected entity.
- **LOW — Inconsistent loading states** (spinners vs. text vs. nothing). Standardize: skeletons for lists, spinners for actions.

### 3.7 Accessibility

- **HIGH — Icon-only buttons lack semantic labels** throughout `widgets/message/`. Screen readers get nothing. Add `Tooltip`/`Semantics` to every icon button (also fixes discoverability, §3.1).
- **MEDIUM — Low-contrast secondary text** (`onSurfaceVariant` at 0.6 alpha) likely fails WCAG AA; audit and fix.
- **MEDIUM — No visible focus outlines** on text fields for keyboard users.

### 3.8 Mobile & polish

- **MEDIUM — Cramped input row on <600px**; move the file picker behind a "+" button on mobile.
- **LOW — Hardcoded 360px settings drawer** can exceed small screens: `min(360, width * 0.9)`.
- **LOW — Generic Material empty-state icons.** A garbanzo-bean mascot/illustration set would give the app a personality for nearly zero cost.
- *(Carried over from `improvement.md`, still endorsed: Mermaid rendering on web via mermaid.js interop, micro-animations, `InteractiveViewer` image lightbox, desktop sidebar collapse.)*

---

## 4. Frontend Engineering Health

### Performance (do these together — they compound)

- **HIGH — Rebuild storm:** every SSE chunk → `notifyListeners()` → full message-list rebuild (`chat_provider.dart:440–463`). Use a per-streaming-message `ValueNotifier<ChatMessage>` + `ValueListenableBuilder` so only the active bubble repaints.
- **HIGH — Markdown re-parsed on every chunk** (`markdown_widget.dart:39–56`). Memoize on content hash; during streaming, render the tail as plain text and only re-parse the markdown on a ~100ms throttle.
- **MEDIUM — Syntax lists recreated each build** (`markdown_widget.dart:53–55`) — make them `static final`.
- **MEDIUM — Four separate `context.watch<ChatProvider>()` calls** per message just for `isSending` (`chat_message_widget.dart:194–251`) — collapse to one `Selector`.
- **MEDIUM — Notification poll runs every 30s forever**, even backgrounded (`notification_provider.dart:14–19`). Tie to `AppLifecycleState`.

### Correctness

- **HIGH — No streaming state machine.** Rapid send/edit/regenerate during an in-flight stream can interleave: `onDone`'s `_reloadCurrentConversation()` (`chat_provider.dart:495–511`) can clobber a newer optimistic edit. Introduce `StreamState {idle, streaming, finalizing}` and gate actions on it.
- **MEDIUM — Stale model closure:** `ChatProvider` captures `selectedModelId` as a callback wired at build time (`chat_page.dart:43–65`). Pass a `ValueNotifier`/`ProxyProvider` instead (also flagged in `improvement.md`).
- **MEDIUM — Local provider instances bypass the tree** (`memory_page.dart:22`, `knowledge_base_page.dart:24` — `_provider = MemoryProvider()` inside state). Provide via the widget tree; fixes lifecycle and double-poll bugs (KB poll timer can run against a disposed provider).
- **MEDIUM — Room socket has no error/reconnect path** (`room_socket_service.dart:39–54`): on network drop, the provider never learns the socket died. Add `onError`/`onDone` handling with backoff reconnect and a "reconnecting…" UI state.
- **MEDIUM — SSE parser silently drops malformed chunks** (`chat_service.dart:287–295`). Surface a parse-error chunk instead of `catch (_) {}`.

### Structure

- **Split the three god-files:** `settings_drawer.dart` (940 lines → one widget per panel), `chat_provider.dart` (682 lines → conversation CRUD vs. streaming vs. tools), `chat_page.dart` (583 lines → app bar / list / drop-zone / error banner).
- **Extract a shared provider error pattern** — the identical `catch (e) { _error = ...; notifyListeners(); }` block appears in 10+ providers. One mixin with typed errors and a retry hook.
- **Add the missing tests that matter:** stream cancellation & mid-stream conversation switch, 401-refresh-retry in `ApiClient`, room socket reconnect. (The SSE parser test that exists is good — extend that style.)

---

## 5. Backend Engineering Health & Security

### Security (verified)

- **HIGH — `rooms_ws.py:46–50` accepts refresh tokens.** `decode_token` is called without checking `payload["type"] == "access"` (the HTTP path checks it). One-line fix.
- **MEDIUM — WebSocket membership is checked only at connect.** A user removed from a room keeps a live socket. Re-validate on each `post` event (cheap — it's one indexed query) or on a heartbeat.
- **MEDIUM — KB upload reads the whole body before the size check** (`knowledge_base.py:40–46`, verified). Check `Content-Length` first / read in chunks; also whitelist MIME types rather than trusting `file.content_type`.
- **MEDIUM — Unescaped `ilike` wildcards** in memory search (`memory_service.py:84`) — escape `%`/`_`, or move to FTS (which §2.2 wants anyway).
- **MEDIUM — Debug CORS allows `*` methods/headers** (`main.py:163`) — tighten even in debug.
- ✅ *Done well:* JWT with `jti` + type claims and rotation, bcrypt cost 12, soft deletes, consistent ownership scoping in conversation queries, file-size limits, clean `get_db` commit/rollback.

### Robustness

- **MEDIUM — No Ollama retry/backoff** anywhere; a blip kills the request (pairs with §2.5).
- **MEDIUM — `_active_streams` entries can leak** on pre-finally exceptions (`chat_service.py:519, 650`) — `finally: pop()`.
- **MEDIUM — `RoomConnectionManager` recursive disconnect-during-broadcast** (already in `improvement.md` — still valid; collect dead sockets, clean up once outside the loop).
- **MEDIUM — Conversation search materializes all matched messages per conversation** (`conversation_service.py:159–225`) — cap per-conversation matches.
- **LOW — Move provider registration to app lifespan** (from `improvement.md`, endorsed) and extract document parsing out of `chat_service.py` into `services/document_parser.py` (likewise endorsed).

### Infrastructure (from `improvement.md`, re-prioritized)

1. **Worth doing soon:** rate limiting on LLM/TTS/STT endpoints (these endpoints are expensive); Alembic *if* the team grows — for a solo project the manual SQL + `create_all` flow is honestly fine.
2. **Defer until there's a scaling need:** Redis broker, Celery/arq. APScheduler + `asyncio.create_task` are adequate at current scale; the embedding-task failure handling (§2.3) matters more than swapping the queue.

---

## 6. Feature Opportunities (new, ranked by value/effort)

1. **Cloud LLM provider (Anthropic/OpenAI)** — the single biggest capability unlock; the abstraction is already shaped for it.
2. **Conversation auto-titling + follow-up suggestions** — cheap-model background calls, big perceived polish.
3. **Per-message feedback (👍/👎)** — doubles as the seed of an eval dataset for prompts, memory extraction, and the room judge.
4. **Conversation folders/tags & message starring** (from `improvement.md` — endorsed, in this order).
5. **"Memory review" moment** — a periodic, gentle "Here's what I've learned about you this week — keep/edit/forget?" flow. Turns the memory system from invisible to delightful, and doubles as the dedup/decay mechanism of §2.2 with a human in the loop.
6. **Export/share a conversation** as markdown (rooms already have export; chats don't).
7. **Debate mode for rooms** (from `improvement.md`) — fun, but after the auto-judge batching fix.

---

## 7. Suggested Roadmap

**Phase 1 — Foundations & quick wins (≈1 week)** — **COMPLETE ✅**
~~WS token-type fix~~ · ~~smart auto-scroll~~ · ~~auto-titling~~ · ~~tooltips/semantics on message actions~~ · ~~"Stopped" badge~~ · ~~stream-state machine~~ (action-epoch guard) · ~~`_active_streams` cleanup~~ (already present) · ~~undo-delete snackbar~~ · ~~KB read-before-check fix~~.
*Done 2026-06-11 (round 4): shared `MessageActionButton` with tooltips + screen-reader button semantics across Copy/Listen/Regenerate/Branch/Edit/Info; interrupted responses keep partial content and show a "Stopped" badge; action-epoch counter prevents the post-stream reload from clobbering newer optimistic edits; conversation delete is optimistic with a 6s undo window (API fires after the window; dispose flushes pending; failed deletes restore the row).*

**Phase 2 — Performance & token truth (≈1–2 weeks)**
~~TokenCounter service~~ ✅ · ~~per-message ValueNotifier streaming~~ ✅ · ~~markdown memoization~~ ✅ · ~~honest context indicator~~ ✅ · ~~summarization prompt upgrade~~ ✅ · ~~Ollama retry/backoff + chunk timeouts~~ ✅.
*Done 2026-06-11 (round 3): rooms WS rejects refresh tokens; KB upload rejects oversized bodies via Content-Length pre-read and binary/mojibake content; Ollama connect retry ×3 with backoff + per-chunk timeouts (300s first / 120s steady); summarization digests tool calls/results and preserves goals/decisions; conversation auto-titling (background task on the conversation's model after the first exchange, frontend refreshes ~4s after stream end). Also fixed: assistant messages now update the in-session relationship collection (second turn on one session no longer looks like a first exchange).*
*Done 2026-06-10 (round 1): TokenCounter service; real context lengths from `ollama show` (+ capability flags on ModelInfo); num_ctx allocation; memory/KB token budgets; context_length stamped in message meta; indicator prefers real per-turn window; fixed think=True 400 against current Ollama for non-thinking models.*
*Done 2026-06-10 (round 2): client num_ctx clamped to server ceiling; metadata-lookup failures no longer cached; num_ctx for internal LLM calls (summarization, room agents, memory extraction); streaming rebuilds isolated to the live bubble via throttled ValueNotifier (~12 pushes/s); markdown parse memoized per content+theme; smart auto-scroll (near-bottom gated) + jump-to-bottom pill; streams cancelled on conversation switch/clear; partial content preserved on Stop. Verified live (E2E on Linux desktop with qwen3.6): thinking + content streaming, auto-collapse on answer, context_length=8192 persisted in message meta, no runtime errors.*

**Phase 3 — Make the AI visibly smart (≈2 weeks)**
~~Memory ranking/budget/dedup/decay + memories-used badge~~ ✅ · RAG threshold + hybrid search + citation chips · tool-progress streaming + human-readable tool bubbles · embedding-task failure status.
*Done 2026-06-11 (round 5): `UserMemory.embedding` (pgvector, migration 011, applied to dev DB); memories embedded on create/update with graceful degradation when the embedder is down; `get_relevant_memories` ranks by cosine similarity to the current message with gentle recency decay (0.001 distance/day) and recency fallback, capped at `memory_top_k` (8); extraction drops exact + semantic (≥0.90) duplicates and reuses candidate embeddings for storage; daily job backfills missing embeddings; `memories_used`/`kb_chunks_used` stamped into message metadata, shown as a header badge with tooltip + Info-panel rows.*

**Phase 4 — Reach & structure (ongoing)**
Cloud provider (deferred by request) · god-file splits (backend + frontend) · ~~settings IA redesign~~ ✅ · ~~onboarding card~~ ✅ · ~~room judge batching~~ ⊘ rejected by benchmark · accessibility audit · feedback buttons → eval loop.
*Done 2026-06-12 (round 7): settings drawer split from one 940-line file into a 94-line shell + 5 section widgets under `drawer_sections/`, regrouped as Pages → This conversation → App settings (memory/KB page links unified with the rest of navigation, drawer width responsive). Room auto-judge batching was built, benchmarked, and REJECTED: one batched call scored 72.1% vs 90.7% for the validated per-agent prompt on the same 43 scenarios (12 FP vs 3) — the negative result is recorded in `scripts/benchmark_auto_judge.py` (`--batched` mode kept for re-testing with future judge models). Shipped instead: per-agent judge calls now run concurrently via asyncio.gather, so wall-clock for N auto agents drops from N×~1.3s toward the slowest single call with zero accuracy change.*
*Done 2026-06-12 (round 6, while the Phase 3 cloud routine runs): RoomConnectionManager dead-socket cleanup no longer recurses (single presence update per broadcast, regression-tested); room WS re-validates membership on every post; dismissible "Getting started" card on the empty state (persisted); transcription failures mapped to actionable messages. (Recording timer + recording-error mapping from the UX review were already implemented.)*

---

*Corrections to agent findings made during verification: notification listing is already capped at 50 (not unbounded); the WebSocket refresh-token gap, the KB full-read-before-size-check, and the absence of auto-titling were all confirmed in source.*
