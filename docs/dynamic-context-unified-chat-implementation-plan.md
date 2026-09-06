# Dynamic Context + Unified Chat Implementation Plan

Status: core implementation is complete and under final live E2E validation. The
HTML mockup remains the interaction/design reference.

Grounding:

- User report `25873364-43ce-428c-9688-44df4f8c5b7f`: one primary chat with AI-managed, visible, editable active context.
- User report `205e8da9-4b45-4d09-8215-551fbaa59266`: larger composer, style/model control, and model-specific normalized thinking effort.
- Approved mockup: `docs/mockups/dynamic-context-unified-chat.html`.

## 1. Product decisions locked by the mockup

1. The default experience is one primary chat. The user can keep talking while Garbanzo detects topic changes and rebuilds the active context.
2. Existing conversations are not merged, rewritten, or deleted. They remain selectable under **Threads** and retain their messages, model, style, tools, mute state, and scheduled-action links.
3. **New topic** returns to topic discovery inside the primary chat. It does not create a new conversation row.
4. A compatibility-only **New thread** action remains inside the Threads tab.
5. Topic discovery is a line-free field of selectable text topics on every platform:
   - phones: vertical, alternating placement;
   - desktop/tablet: horizontal rows;
   - promoted subtopics are explicitly labeled `Subtopic in <parent>`;
   - `Something new` exists only under Explore;
   - there is no Surprise me action.
6. Users may start at any topic depth, including a broad parent topic.
7. Active context shows only the current included/pinned material and why it is included. There is no Activity tab or context-event timeline.
8. A response style is a reusable bundle of model, system prompt, and thinking effort.
9. Thinking effort always uses the same four-position `off / low / medium / high` scale in the UI. The backend maps each available position to the selected model's native reasoning control. Models may expose fewer than four positions; unmapped positions remain visible but disabled.
10. Personal topics are generated from the user's actual messages and conversations. Hand-authored suggestions exist only in Explore; they never masquerade as learned personal topics.
11. Each personal topic owns a versioned, evidence-grounded context pack. It tracks confirmed facts, decisions, preferences, constraints, rejected/superseded ideas, deadlines, and open loops—not only a prose summary.
12. New turns appear as a real-time delta within seconds. An hourly job consolidates dirty topics for users with new material, and periodic evidence-first rebuilds prevent summary drift.

## 2. Compatibility and migration strategy

The first release must be additive.

- Existing `Conversation` rows remain legacy threads and continue using every current endpoint.
- Add one lazily created primary conversation per user. Do not concatenate old messages into it; legacy threads become retrievable context sources.
- Existing thread URLs/deep links continue to open the original conversation.
- `POST /messages/{id}/branch` keeps creating a legacy thread, including when branching from the primary chat.
- Scheduled actions keep their existing `conversation_id`. No scheduled action is silently moved to the primary chat.
- Search includes primary-chat messages and legacy threads. A result opens its owning surface and scrolls to the message.
- Deleting a legacy thread retains current soft-delete behavior. Deleting/resetting the primary chat is not exposed in v1; Fresh start clears active context without deleting messages.

## 3. Persistence design

### 3.1 Migrations `038`–`040`: primary chat, topic evidence, and context cache

Split this schema into three idempotent migrations so deploy/rollback diagnosis stays tractable: `038_primary_topic_graph.sql` (conversation/topic/alias identity), `039_topic_evidence_cache.sql` (memberships, assertions, exclusions, context versions), and `040_dynamic_context_state.sql` (ingestion queue/state and active-context items). Add foreign keys that cross those groups only after both referenced tables exist.

Extend `conversations`:

| Column | Type | Purpose |
|---|---|---|
| `is_primary` | boolean, default false | Marks the user's unified chat. |
| `active_topic_id` | nullable FK to `topics`, `ON DELETE SET NULL` | Current detected or selected topic. |
| `topic_is_pinned` | boolean, default false | Prevents automatic topic switching. |
| `context_version` | bigint, default 0 | Monotonic version for stale-client protection. |

Add a partial unique index enforcing at most one non-deleted primary conversation per user.

Create `topics`:

| Column | Purpose |
|---|---|
| `id`, `user_id` | User-owned UUID and owner FK. |
| `parent_id` | Nullable self-FK for the topic hierarchy. |
| `label`, `normalized_label` | Display label and deduplication key. |
| `origin` | `history`, `suggested`, or `manual`. |
| `base_score` | Stable relevance estimate in `[0,1]`. |
| `signal`, `signal_expires_at` | Short UI reason such as `active now` or `due soon`. |
| `last_active_at`, `mention_count` | Recency/frequency signals. |
| `status`, `canonical_topic_id` | `active`, `merged`, or `archived`; merged topics redirect without breaking old links. |
| `current_context_version_id` | Pointer to the last validated materialized context pack. |
| `dirty_since`, `last_consolidated_at` | Real-time/hourly consolidation state. |
| `metadata` | JSONB for open-loop, deadline, and diversity features. |
| timestamps | Auditing and cache invalidation. |

Indexes: `(user_id, parent_id)`, `(user_id, last_active_at DESC)`, and a unique `(user_id, parent_id, normalized_label)`.

Create `message_topics` as the evidence membership layer:

- composite primary key `(message_id, topic_id)`;
- `confidence`, `is_primary`, `segment_start`, `segment_end`, `source_authority`, and `created_at`;
- the link is allowed to be many-to-many because a turn may update both `Finance` and `Retirement`;
- cascade when either message or topic is deleted.

Create `topic_assertions`. These are the typed units from which context is built:

| Column | Purpose |
|---|---|
| `id`, `topic_id` | User-scoped assertion owned through a topic. |
| `kind` | `fact`, `decision`, `preference`, `constraint`, `goal`, `deadline`, `open_loop`, or `proposal`. |
| `content`, `normalized_key`, `embedding` | Concise claim, dedupe key, and retrieval vector. |
| `status` | `active`, `uncertain`, `superseded`, `rejected`, or `expired`. |
| `authority`, `confidence` | Provenance rank and extraction certainty. |
| `valid_from`, `valid_until` | Temporal scope; absence means currently unbounded, not eternally true. |
| `superseded_by_id` | Explicit contradiction/correction chain. |
| `first_seen_at`, `last_confirmed_at` | Recency and repeated-confirmation signals. |

Create `topic_assertion_evidence` rather than storing evidence IDs in a JSON array:

- composite identity `(assertion_id, message_id, segment_start, segment_end)`;
- `relation` is `supports`, `corrects`, `rejects`, or `adopts`;
- store a hash of the exact source span so deterministic validation detects stale offsets after an edit;
- foreign keys provide real deletion/cascade integrity;
- source ownership is validated before insertion and again before compilation.

Assistant text may help interpret a dialogue but cannot independently create a confirmed user fact. Authority order is: latest explicit user correction; explicit user statement; tool-verified result; assistant proposal explicitly accepted by the user; unaccepted assistant/tool material. The final category stays a `proposal` or `uncertain` and is never injected as fact.

Create `topic_exclusions` for durable negative knowledge:

- scope: one assertion, source, semantic concept, topic, or all topics;
- origin: explicit context-panel removal, explicit user statement, or admin/privacy deletion;
- `reason`, `source_message_id`, `concept_embedding`, `created_at`, and nullable `revoked_at`;
- hard-filter matching evidence before ranking or LLM compilation;
- ambiguous natural-language rejections do not become broad exclusions without confirmation.

Rejected information is not silently forgotten and later rediscovered. It remains auditable as rejected evidence, while the generated prompt contains only the smallest relevant guardrail—for example, `Do not recommend X; the user rejected it on <date>`—and never presents X as an active option. A later explicit user reversal revokes the exclusion and creates a new evidence chain. “Forget/remove X” is different: it creates a privacy deletion/exclusion whose content is absent even from negative guardrails.

Create immutable `topic_context_versions`:

| Column | Purpose |
|---|---|
| `id`, `topic_id`, `version` | Stable context-pack version. |
| `context_json` | Typed current state: goal, facts, decisions, preferences, constraints, negative guardrails, deadlines, and open loops. |
| `short_summary` | UI-safe description; not the source of truth for the next version. |
| `source_event_watermark` | Highest ingestion event represented. |
| `model_id`, `model_revision`, `provider`, `prompt_version` | Reproducibility and safe prompt migrations even when a provider alias advances. |
| `input_tokens`, `output_tokens`, `validation_status` | Cost and quality telemetry. |
| `created_at` | Immutable creation time. |

Every item inside `context_json` carries assertion/evidence IDs. A consolidation result containing an unknown, deleted, cross-user, or ungrounded ID fails validation and is not promoted to `topics.current_context_version_id`.

Create `topic_ingestion_events` and `topic_ingestion_state`:

- message create/edit/delete and conversation delete/restore enqueue an event in the same database transaction as the source mutation;
- monotonically increasing event IDs are the only processing watermark;
- per-user state stores `last_realtime_event_id`, `last_consolidated_event_id`, lease/error fields, and retry time;
- unique operation/source keys make retries idempotent;
- no hourly full-table scan and no lost work after a process restart.

Create `topic_aliases` so hourly merge/split/reparent operations preserve old topic links, breadcrumbs, user pins, and context references. Merges redirect to one canonical topic; splits reassign evidence memberships and retain the former label as an alias until the new structure is stable.

Create `active_context_items`:

| Column | Purpose |
|---|---|
| `id`, `conversation_id` | Current-context record owned through the conversation. |
| `source_type` | `topic_assertion`, `message`, `thread`, `memory`, `knowledge`, or `attachment`. |
| `source_id`, `source_meta` | Source locator; metadata handles an attachment within message JSON. |
| `topic_id` | Optional topic affinity. |
| `state` | `dynamic`, `pinned`, or `excluded`. |
| `reason` | User-facing explanation of selection. |
| `relevance_score`, `token_count` | Ranking and budget information. |
| `last_selected_at` | Currentness and cleanup. |

Use a unique constraint on `(conversation_id, source_type, source_id)`. An `excluded` row is a durable suppression rule; a `dynamic` row may be replaced on the next context version; a `pinned` row survives topic changes and Fresh start only when the user explicitly chooses to keep pins.

Do not add a context-activity table. For reply-level reproducibility, store a compact immutable context snapshot in the assistant `Message.meta` (`context_version`, active topic, source identifiers, scores, and token totals). This is diagnostic metadata, not a user-facing Activity feed.

### 3.2 Migration `041_model_thinking_levels.sql`

Add `available_models.thinking_levels` as nullable JSONB and `default_thinking_level` as nullable string.

- `thinking_levels` stores an ordered capability mapping, not just a count. Each entry contains a normalized `level` and the provider-native scalar/value to send for that model; for example, a three-state model could map `low → light`, `medium → standard`, and `high → deep`, leaving `off` unavailable.
- Normalized values are unique and limited to `off`, `low`, `medium`, and `high`. Native values are provider-owned and may be booleans, strings, numeric budgets, or structured provider options.
- A model is not required to provide all four positions. Missing normalized positions are intentionally disabled in the client.
- `NULL` means capability metadata has not been established, not “all levels.”
- Preserve `supports_thinking` in API responses for compatibility during rollout.
- `Conversation.thinking_level` and `Style.thinking_level` store only the normalized value, never the provider-native value. Existing `NULL` retains provider-default semantics. The UI may show `Auto` for legacy null values until the user chooses an explicit supported level.

## 4. Backend services

Architecture at a glance:

```text
committed message/edit/delete
        │
        ├── same transaction ──> durable ingestion event
        │                              │
        │                              ├── seconds: topic match + validated live delta
        │                              │                └── next turn sees it immediately
        │                              │
        │                              └── mark user/topics dirty
        │                                               │
        │                                     hourly structured curator
        │                                               │
        │                                  validated immutable context pack
        │                                               │
topic selected/current message ──> request-time compiler: pack + live delta
                                                    + exclusions + raw evidence
                                                               │
                                                        bounded LLM context
```

### 4.1 Primary conversation

Add `ConversationService.get_or_create_primary(user_id, style defaults...)` using a transaction plus the partial unique index to handle concurrent first opens.

Add `POST /api/v1/chat/conversations/primary` as an idempotent ensure operation. Return the existing primary conversation or create it using the user's default/last-used style settings supplied through the existing creation path.

Extend conversation schemas with `is_primary`, `active_topic_id`, `active_topic`, `topic_is_pinned`, and `context_version`.

Extend `GET /chat/conversations` with `kind=all|primary|thread`. The Threads UI requests `thread` so pagination totals never include the primary chat.

### 4.2 Automatic topic graph from history

Create the self-contained `backend/app/topics/` feature package: its models,
schemas, API router, services, semantic curator, and scheduler job live there.
Migrations remain under `backend/migrations/`, and in-app help stays in
`backend/app/docs/help/topics.md` for loader discovery.

Personal mode is derived from the user's primary-chat and legacy-thread messages. Conversation titles are only weak hints; the actual user turns, accepted/rejected assistant proposals, tool results, dates, edits, and deletions are the evidence. Explore remains a separate suggestion catalog.

Topic formation pipeline:

1. Split a conversation into coherent turn groups/episodes, preserving user → assistant → tool relationships.
2. Embed the groups with the deployment's existing embedding provider and retrieve nearby active topics.
3. Attach to a topic only above a calibrated similarity threshold. Otherwise create a provisional topic with a stable UUID.
4. Let a structured curator refine the label, parent, aliases, assertions, open loops, and importance. It may propose merge/split/reparent operations but never mutates rows directly.
5. Validate and apply assertion operations transactionally. Structural merge/split/reparent changes require a strong score margin and persistence across two consolidation cycles unless the user explicitly requests the change; this prevents an hourly “dancing tree.” Preserve redirects and source memberships.
6. Rank the materialized graph for discovery without changing its semantic structure.

Hierarchy must express actual breadth, not arbitrary clustering. For example, `Finance → Retirement` is valid when retirement evidence is a coherent recurring subset; a single retirement mention stays attached to Finance until enough evidence justifies a child. Starting a parent topic retrieves only the relevant/high-importance descendants for the current request, not every child indiscriminately.

Endpoints:

| Endpoint | Behavior |
|---|---|
| `GET /topics?mode=personal|explore` | Personal returns the user's materialized graph and live deltas; Explore returns suggestions. |
| `POST /conversations/{id}/topics/activate` | Activates an existing topic or free-text provisional topic, starts context prewarming, preserves explicit pins, and increments `context_version`. |
| `PATCH /conversations/{id}/topic` | Pin/unpin or redirect the active topic. |
| `GET /topics/{id}/context-status` | Current pack version, source watermark, live-delta count, freshness, and preparation state. |
| `POST /topics/{id}/prepare` | Idempotent prewarm used when the user selects/opens a topic. |

The response node contains `id`, `parent_id`, `label`, `origin`, `score`, `signal`, `child_count`, `children`, `starter_prompts`, `can_start`, `context_status`, and `updated_at`.

Discovery ranking is separate from context correctness. Initial ranking signals are semantic relevance to recent user messages, exponential recency decay, repeated engagement, unresolved/open-loop state, deadline urgency, explicit importance/pins, and a diversity penalty. These decide prominence/size; they never decide whether an assertion is true.

Suggested Explore topics come from a cached, user-safe suggestion pool. `Something new` is an Explore root. The backend returns ranked candidates; the client decides how many promoted subtopics fit (very narrow phone: up to two, normal phone: up to three, wider layouts: up to four).

### 4.3 Real-time ingestion: fresh within seconds

Every committed message mutation writes a `topic_ingestion_event` in the same transaction. After an assistant turn finishes, launch a best-effort detached ingestion task with its own database session, following the existing `DetachedChatStream`/background-session lifetime rule. The durable event—not the task—is the reliability mechanism; the hourly worker catches anything missed after failure or restart.

For each unprocessed event, the real-time path:

1. Revoke derived evidence for an edit/delete before processing replacement content.
2. Build the coherent turn group and classify it against current topic embeddings.
3. Attach the group to one or more topics with confidence and mark one primary when warranted.
4. Run a small structured extraction over only this turn plus minimal neighboring context, producing candidate assertions and explicit reject/correct/adopt signals.
5. Validate evidence IDs, authority, timestamps, and ownership; upsert provisional assertions idempotently.
6. Mark affected topics dirty and update their live-delta overlay.
7. Emit `topic_update` for clients currently showing discovery/context.

This path does not rewrite the stable context pack and does not delay the already-completed assistant response. The next turn sees `stable pack + validated live delta`, so it does not wait for the hourly job. A selected topic is created immediately even before it has messages, which makes an intentional new topic visible in real time.

Natural-language corrections are first-class. Explicit phrases such as “I changed my mind,” “don’t use that,” or “we ruled that out” may supersede/reject an assertion when the referenced target is unambiguous. Vague language creates an `uncertain` candidate and may trigger a lightweight confirmation in the UI; it never silently erases a broad concept.

### 4.4 Hourly consolidation and cache lifecycle

Register one APScheduler interval job with `coalesce=True` and a single-instance guard. Every hour it claims only users whose ingestion watermark is newer than their consolidation watermark. Use a PostgreSQL advisory lock or lease row so multiple backend replicas cannot consolidate the same user concurrently.

For each dirty user:

1. Drain/retry real-time ingestion events through a fixed watermark.
2. Group dirty topics by semantic neighborhood so merges/splits are considered together.
3. Give the curator the current typed pack, validated assertions, exclusions, aliases, and only the new/changed evidence since the previous watermark—not all raw history.
4. Request schema-constrained operations: retain/update/supersede/reject assertion, create/merge/split/reparent topic, update open loop/deadline, and set importance signals.
5. Validate every operation against source evidence and invariants, then atomically write a new immutable context version and advance the current pointer/watermark.
6. Leave the previous version active on timeout, schema failure, ungrounded output, or partial processing; retry with backoff.

The hourly database context pack is the product cache. Provider prompt/KV caching may reduce model cost but is never part of correctness or freshness.

Incremental consolidation must not compound summary error. Every context item retains source IDs, and a weekly maintenance pass—or an earlier pass after a prompt/model change, 500 new evidence items, repeated contradictions, or low validation score—rebuilds the topic from original active evidence rather than from the prior summary. Compare the rebuild with the current pack before promotion and record merge/split redirects.

Edits, soft-deleted conversations, restored conversations, memory deactivation, and knowledge-document deletion invalidate affected memberships immediately. Until reconsolidation, request-time compilation hard-filters unavailable sources by ownership/status, so stale cached text can never resurrect deleted information.

### 4.5 What a smart topic context contains

The curator produces typed state rather than one narrative blob:

| Section | Inclusion rule |
|---|---|
| Topic identity/current goal | Concise scope and what the user is currently trying to accomplish. |
| Confirmed facts/current state | Active, grounded assertions; newer explicit corrections win. |
| Decisions | Choices the user actually made, with date and evidence. |
| Preferences and constraints | Relevant user requirements, not generic memories. |
| Negative guardrails | Minimal reminders for rejected/superseded options when needed to avoid repeating them. |
| Deadlines/time-sensitive state | Validity dates and urgency; expired items are excluded or labeled historical. |
| Open loops | Unresolved questions/next actions with last activity. |
| Uncertain candidates | Kept for future confirmation; never injected as facts. |

Truth/authority rules are deterministic around the LLM:

- the newest explicit user correction supersedes an older user statement;
- repeated statements increase confidence but cannot override a later correction;
- assistant suggestions stay proposals unless the user accepts/adopts them;
- tool output is attributed to the tool and can become current state, but not a personal preference;
- a user/UI exclusion is a hard filter that ranking and the curator cannot override;
- expired or superseded state is omitted unless the current question explicitly asks for history;
- unrelated global memories and sibling-topic material are not pulled in merely because they are popular.

Grounding is two-stage. Deterministic validation checks schema, ownership, source-span hashes, temporal fields, allowed operation transitions, and exact evidence existence. A semantic verifier then checks that each new/changed high-impact assertion is entailed by its cited span and that reject/correct/adopt relations point to the intended target. Failed or ambiguous items remain `uncertain`; they do not enter the pack. Negative exclusions require the highest precision threshold because a false exclusion is more damaging than missing one contextual detail.

### 4.6 Request-time context compilation and first-turn preparation

Create `TopicContextCompiler` as the only component allowed to turn stored topic state into generation input:

1. Resolve the selected/detected topic. Respect a pinned/manual topic; require a confidence margin plus two-turn hysteresis before an automatic switch.
2. Load the latest validated context pack and overlay real-time assertions through the latest ingestion watermark.
3. For a parent topic, retrieve relevant descendants using the current user message; for a child, include only relevant ancestor constraints and explicitly related topics.
4. Apply topic/global exclusions and source-ownership/deletion filters before scoring.
5. Reserve the current turn plus a recent continuity window, then add pins, negative guardrails, high-relevance typed assertions, open loops/deadlines, and finally coherent raw evidence groups.
6. Retrieve legacy-thread messages, memories, KB chunks, and attachments only when they match the active topic/current request. Expand a selected message into its coherent local turn group and restore chronology.
7. Deduplicate typed assertions against raw evidence so the model does not receive the same fact three times.
8. Compile a delimited `<topic_context>` block that labels provenance and treats historical content as data, never instructions.
9. Enforce the final token budget after system/style/tool overhead. Drop the lowest-ranked optional group; never slice arbitrary messages or remove a relevant negative guardrail.
10. Persist the exact topic/context/source version IDs and token totals in assistant `Message.meta`.

Initial candidate scoring remains explainable: semantic similarity `0.35`, active-topic affinity `0.20`, authority/confidence `0.15`, recency/temporal validity `0.10`, open-loop continuity `0.10`, deadline importance `0.05`, and source quality `0.05`. Explicit pins and applicable negative guardrails bypass ranking. Tune these weights from retrieval evaluations rather than intuition after v1.

Refactor `ChatContextBuilder.build_history_with_system_prompt()` to accept compiler-selected message groups and compiler-selected memory/KB inputs. Preserve the existing full-history/rolling-summary path for legacy threads until the unified-chat rollout is complete.

Freshness behavior:

- **Fresh pack:** compile synchronously without an LLM call; target under 250 ms.
- **Pack plus uncondensed live delta:** overlay validated delta and compile; do not wait for the hourly curator.
- **Stale pack after edits/deletes:** hard-filter invalid evidence and compile from the safe remainder; queue urgent consolidation.
- **No pack but relevant history exists:** topic activation starts prewarming while the user types. If the first message arrives first, emit `context_preparing`, wait up to 12 seconds for one high-quality bootstrap, then use deterministic raw-evidence retrieval if it fails/times out. Continue the job so the next turn is improved.
- **Brand-new topic with no history:** no artificial wait; use the current message/recent turns and create the first live delta after the turn.

Failure behavior is mandatory: pinned valid items, applicable exclusions, and the recent-turn window remain available even if embeddings, the curator, or consolidation are down. The user gets a response, and the UI shows that historical context is temporarily limited rather than pretending it is complete.

### 4.7 Curator model strategy and evaluation

The curator model is a separate deployment role from the conversational model: `TOPIC_CURATOR_PROVIDER`, `TOPIC_CURATOR_MODEL`, `TOPIC_CURATOR_THINKING`, optional `TOPIC_REALTIME_MODEL`, and bootstrap timeout/concurrency settings. Private history must never cross from a self-hosted/local deployment to a cloud provider without explicit deployment/user consent.

Local Ollama can request JSON Schema through `format`, but cloud-tagged Ollama models must not be assumed to enforce it: a live GLM 5.3 Flash check returned markdown despite the schema request. The production path therefore combines a strict JSON-only prompt, raw Pydantic parsing, one corrective retry, exact evidence-subset validation, and deterministic fallback. Runtime failures stay inside the configured privacy boundary—never silently fall back from local to cloud.

Research snapshot (2026-08-30):

- **Initial deployed cloud candidate: `glm-5.3-flash:cloud` through Ollama.** It is used only when the administrator explicitly selects `cloud_allowed`; the deterministic validator, rather than the provider capability flag, is the trust boundary.
- **Strong alternative to evaluate: `gemini-3.7-flash`.** Google documents structured outputs, caching, a 1,048,576-token input limit, and low/medium/high thinking. Adding a new provider is justified only if the eval gain offsets operational complexity. See the [official model card](https://ai.google.dev/gemini-api/docs/models/gemini-3.7-flash).
- **Local/private option:** use a local Ollama model that passes the same eval and JSON Schema contract. Ollama documents local schema-constrained output and embedding support, but its docs currently state that Ollama Cloud does not support structured outputs. Do not assume a `:cloud` model has the same guarantee. See [Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs) and [Ollama embeddings](https://docs.ollama.com/capabilities/embeddings).

Do not select the production model from vendor benchmarks alone. Build a blinded, versioned evaluation corpus of realistic conversation histories with human-approved topic graphs/context packs. Score:

- topic purity, merge/split accuracy, and hierarchy stability;
- grounded assertion precision/recall and evidence citation validity;
- correction/rejection precision (false rejections are heavily penalized);
- temporal correctness and open-loop/deadline retention;
- prompt-injection resistance from message content;
- context usefulness judged on downstream answer quality;
- schema failure/retry rate, latency, and cost.

Run candidate models in shadow mode on opt-in/test histories. Initial launch gates: 100% deterministic evidence-link integrity, at least 98% human-rated promoted-assertion precision, at least 99.5% rejection precision, zero rejected-item resurrection in the safety set, zero cross-user evidence, and a meaningful downstream-answer win over embeddings + recent-history baseline. Store model ID/revision and prompt version/hash on every pack so a model change can trigger controlled evidence-first rebuilds.

### 4.8 Active context API

Create `backend/app/topics/active_context_schemas.py` and endpoints:

| Endpoint | Behavior |
|---|---|
| `GET /conversations/{id}/context` | Current topic, pack/live watermarks, readiness/freshness, token summary, pinned and dynamically selected items. |
| `POST /conversations/{id}/context/items` | Add a message/thread/memory/file/KB source after ownership validation. |
| `PATCH /conversations/{id}/context/items/{item_id}` | Pin, unpin, exclude, or restore an item using optimistic `context_version`. |
| `POST /conversations/{id}/context/fresh-start` | Clear active topic and dynamic items; request explicitly says whether pins survive. |

Return only current state. Do not expose an Activity endpoint in v1.

Before the first answer chunk, emit an SSE `context_update` event containing `context_version`, active-topic summary, and counts. The frontend uses it to update the Active context badge/panel. Existing clients ignore unknown SSE types, so verify that behavior before enabling the event.

### 4.9 Model-specific thinking levels

Extend the internal `app.services.llm_provider.ModelInfo` with ordered `ThinkingLevelCapability` entries containing `normalized_level` and `provider_value`. Extend the public `app.schemas.chat.ModelInfo` with:

- `thinking_levels: list[ThinkingLevel] | None`
- `default_thinking_level: ThinkingLevel | None`

The public API exposes only the normalized supported positions; the frontend does not need to understand provider-native settings. Add a provider adapter that translates the stored normalized choice to the native request option immediately before generation. For Ollama:

1. use provider/model metadata when it reports graded effort;
2. convert that native scheme into an explicit, monotonic normalized mapping;
3. allow an admin override stored on `AvailableModel` for models whose metadata is absent or incomplete;
4. use a tested model-family capability registry only where metadata is absent;
5. never infer four levels—or invent intermediate levels—from `supports_thinking=True` or from the number of native states alone.

Examples: a binary off/on model may deliberately expose only `off` and `high`; a three-state model may expose `low`, `medium`, and `high` with `off` disabled. The provider registry decides these semantic positions explicitly, so the frontend never guesses how a native setting should be labeled.

Validate conversation/style writes against the chosen model. Reject an unsupported explicit level with HTTP 422 and return the supported list. This prevents stale clients or imported styles from storing impossible combinations.

## 5. Flutter implementation

### 5.1 Models, services, and providers

Add under `lib/features/topics/`:

- `models/topic_node.dart`
- `models/active_context.dart`
- `services/topic_service.dart`
- `services/active_context_service.dart`
- `providers/topic_discovery_provider.dart`
- `providers/active_context_provider.dart`

Extend `Conversation` and `ModelInfo` Freezed models for the new API fields and regenerate committed `.freezed.dart`/`.g.dart` files.

`TopicDiscoveryProvider` owns mode, path, selected leaf, cached trees, promoted count, context preparation/freshness, and loading/error state. It applies `topic_update` deltas without discarding the user's current path. It must not own chat messages.

`ActiveContextProvider` owns the current context/version and optimistic pin/remove operations. On a 409/version conflict it reloads and reapplies the user's intent once.

`ChatProvider` remains the message/SSE owner. It forwards `topic_update` and `context_preparing` to `TopicDiscoveryProvider`, forwards `context_update` into `ActiveContextProvider`, and uses `get_or_create_primary` when entering the primary surface.

### 5.2 Primary landing and topic field

Create:

- `widgets/topics/topic_landing.dart`
- `widgets/topics/topic_field.dart`
- `widgets/topics/topic_button.dart`
- `widgets/topics/topic_breadcrumbs.dart`
- `widgets/topics/topic_starter_card.dart`

Rules:

- Render semantic buttons, not a custom canvas hit-test layer.
- Use `LayoutBuilder`: horizontal two-row placement above the phone breakpoint; vertical alternating placement below it.
- Promote only candidates that fit while preserving a minimum 48dp non-overlapping tap target.
- Promoted items render `Subtopic in <parent>` and a chevron.
- Parent topics remain directly startable and expose their child count.
- Activating a learned topic immediately starts context prewarming; the user can type while it runs.
- Hide the landing completely as soon as a message is sent or a topic is activated.
- Preserve keyboard focus order, screen-reader labels, reduced motion, dark theme, and 200% text scaling.

Replace `EmptyChatState` only for the primary conversation. Legacy threads continue using their current empty state.

### 5.3 Sidebar and thread preservation

Refactor `ChatSidebar` from two to three first-class tabs:

1. **Topics** — current topic landmarks in the primary chat and the discovery entry point.
2. **Threads** — reuse `ConversationListWidget` with `kind=thread`; selection continues through the existing `_selectConversation` path.
3. **Rooms** — reuse the current rooms tab unchanged.

The Threads tab keeps search, pin, mute, delete/undo, and an explicitly labeled **New thread** action. It never relabels an old conversation as a topic.

On mobile, the same three tabs live in the drawer. Selecting a thread closes the drawer and opens the exact message history. Topic landmarks jump within the primary chat using message IDs/sequence positions; load older pages first when the landmark is outside the current 60-message window.

### 5.4 Active context panel

Create `widgets/active_context_panel.dart` and supporting item widgets.

The panel contains:

- current topic with Pin and Redirect;
- token/context meter;
- next-turn preview summary;
- Pinned by you;
- Selected by Garbanzo;
- Add source;
- per-item Why included, Pin/Unpin, Remove/Exclude.

There is no tab bar and no Activity section. Wide layouts use a side panel; narrow layouts use a modal bottom sheet/full-height drawer. All mutations show immediate optimistic state and recover on API failure.

### 5.5 Composer and New topic

Refactor `MessageComposer` to support an integrated bottom toolbar while retaining its shared use in rooms. Add optional slots rather than hard-coding chat-only controls into the room composer.

In `ChatInputWidget`:

- use `Icons.add_comment_outlined` (or a small custom chat-plus icon if the Material glyph is visually unclear) for **New topic**;
- on desktop show icon + label; on phones show the icon with tooltip/semantics;
- New topic activates the discovery landing and preserves history;
- keep attachment/folder, dictation, Talk Mode, send, stop, and mention-autocomplete behavior;
- make the text area use the approved larger rounded container.

### 5.6 Response style in the composer

Reuse `StyleProvider`, `ModelProvider`, `SystemPromptProvider`, the existing style APIs, and the matching logic in `style_picker.dart`.

Refactor `StylePickerPanel` into a reusable composer-anchored popover on desktop and bottom sheet on mobile. It contains:

- saved/built-in styles;
- model selector;
- editable Instructions (system prompt);
- normalized thinking effort segmented control;
- Save style / set default actions.

Always render the segmented control in the fixed `Off / Low / Medium / High` order. Enable only values in `ModelInfo.thinkingLevels`, and leave every unavailable position visible and disabled so the scale stays understandable across model changes.

Add a compact effort chip beside the style button. One tap cycles only through the enabled normalized values; opening the full picker allows direct selection. If the model exposes only one level, hide or disable the quick chip.

For an unsaved custom style, patch the live conversation directly with the existing model/system-prompt/thinking fields. When the user saves it, create/update a `SystemPromptTemplate` first, then store its ID in `Style`, matching the current persistence model rather than adding duplicate inline prompt storage.

When a model changes:

- keep the current effort if supported;
- otherwise choose the model's declared default;
- explain the adjustment in a snackbar;
- disable unsupported effort buttons;
- send the provider-native mapped value during generation while persisting only the normalized selection;
- never mutate a saved style unless the user explicitly saves changes.

## 6. Delivery sequence

### Phase 1 — Capability contract and composer style control

- Add exact thinking levels to provider/API/admin metadata.
- Validate style/conversation writes.
- Move/refactor the existing style picker into the composer.
- Add the quick effort chip and larger composer.
- This phase can close report `205e8da9...` after deployment.

### Phase 2 — Primary conversation and compatibility shell

- Add `is_primary` migration and ensure-primary endpoint.
- Add Topics / Threads / Rooms sidebar tabs.
- Preserve all legacy thread operations.
- Add New topic vs New thread distinction.

### Phase 3 — Evidence foundation and real-time topics

- Add topic/alias, ingestion-event, membership, assertion, and exclusion persistence.
- Transactionally enqueue every message/conversation mutation.
- Implement idempotent real-time matching/extraction and live-delta overlays.
- Backfill existing history in bounded per-user batches without blocking startup.
- Build responsive topic discovery, activation, breadcrumbs, parent-topic start, and starter prompts.
- Gate: new turns appear in the correct provisional topic within seconds; edits/deletes/rejections invalidate immediately.

### Phase 4 — Curator evaluation and hourly context packs

- Implement the provider-independent structured curator contract and capability checks.
- Build the evidence-grounded JSON schema, validator, immutable context versions, and atomic promotion.
- Create the golden evaluation corpus; compare DeepSeek V4 Flash/Pro, eligible local Ollama models, and any justified alternate provider.
- Add dirty-user hourly consolidation with lease/advisory lock, retry/backoff, and per-user cost limits.
- Add evidence-first periodic rebuild and model/prompt-version migration tooling.
- Gate: consolidation passes grounding, rejection, temporal, hierarchy, injection, cost, and latency thresholds before any pack is used for generation.

### Phase 5 — Active context control plane

- Add current context endpoints/provider/panel.
- Implement pin, exclude, restore, add, redirect, Fresh start, context readiness, and prewarming.
- Display stable-pack versus live-delta items through a single current Active context view; no Activity tab.
- Do not integrate topic packs into LLM input yet; validate generated state against source evidence and user controls first.

### Phase 6 — Request-time compiler and generation integration

- Integrate topic/descendant resolution, exclusions, authority-aware assertion selection, scoring, token budgets, coherent turn expansion, and raw-evidence fallback.
- Refactor `ChatContextBuilder` to receive compiler-selected history/memory/KB rather than all messages.
- Add `topic_update`, `context_preparing`, and `context_update` SSE plus message metadata snapshots.
- Exercise fresh pack, live delta, stale/deleted evidence, cold bootstrap, provider outage, and legacy-thread fallback paths.
- Gate: downstream answer eval demonstrates that the compiled context improves relevance without resurrecting rejected/expired information.

### Phase 7 — Rollout and cleanup

- Enable for the test/admin user first.
- Compare context precision, token usage, and response regressions against legacy chat.
- Enable primary chat by default after acceptance gates pass.
- Keep Threads indefinitely; do not schedule destructive migration.
- Close report `25873364...` only after production deployment and health verification.

## 7. Testing plan

### Backend

- Migration idempotency and partial unique primary-conversation index.
- Concurrent ensure-primary requests return one row.
- Cross-user topic/context source IDs return 404/403.
- Transactional ingestion-event creation for message create/edit/delete and conversation delete/restore.
- Event retry idempotency, crash recovery, watermark advancement, lease expiry, advisory-lock behavior, and multi-replica exclusion.
- Turn segmentation and many-to-many topic membership, including one conversation that changes topics repeatedly.
- Provisional topic creation, alias resolution, two-cycle structural hysteresis, merge/split/reparent stability, and redirect preservation.
- Topic ranking recency, urgency, diversity, open-loop, and promoted ordering independently of assertion truth.
- Structured-curator schema rejection, unknown/cross-user evidence rejection, atomic version promotion, and previous-version preservation on failure.
- Authority matrix: assistant-only claim stays a proposal; explicit user adoption promotes it; a newer correction supersedes it; tool output does not become a preference.
- Explicit and ambiguous rejection handling, reject-versus-forget semantics, semantic exclusion hard filter, later reversal, and prevention of rejected-item rediscovery.
- Temporal validity: future deadline, passed deadline, expired state, and historical-query override.
- Incremental hourly consolidation versus evidence-first rebuild, including no summary-of-summary drift across many versions.
- Topic pin hysteresis, manual redirect, parent-topic descendant selection, and sibling-topic isolation.
- Stable-pack + live-delta overlay, edit/delete invalidation before consolidation, and cold-bootstrap timeout/fallback.
- Context scoring, excluded-item hard filter, pinned priority, assertion/evidence deduplication, coherent turn expansion, deterministic token-budget trimming, and failure fallback.
- Active-context optimistic version conflicts.
- Exact model thinking-level mapping, normalized serialization, provider-native request translation, and 422 validation.
- SSE `topic_update` / `context_preparing` / `context_update`, disconnect recovery, regenerate, edit, and tool-loop compatibility.
- Prompt-injection fixtures where conversation text attempts to alter curator rules, evidence IDs, user scope, or system instructions.
- Privacy modes: local-only deployments never invoke a cloud curator; cloud consent/config changes trigger controlled dirty rebuilds.
- Legacy conversation CRUD, branch, scheduled actions, search, mute, and soft delete remain unchanged.

Use focused `just be-test ...` during development, then `just be-test`.

### Flutter

- Freezed JSON parsing for new topic/context/capability fields.
- Topic provider mode/path/promotion state.
- Golden/widget coverage at 320×568, 390×844, tablet, and desktop widths.
- No topic overlap or composer coverage; desktop horizontal and phone vertical orientation.
- Promoted subtopic label and tap semantics.
- Parent topic activation and complete landing dismissal.
- Topic preparation/loading/limited-context states do not block typing and are announced accessibly.
- New topic preserves messages; New thread creates a separate legacy conversation.
- Threads tab selects exact old history and retains search/pin/mute/delete.
- Active context has no Activity tab.
- The four normalized effort positions stay visible; model switches disable unmapped positions and quick cycling never selects one.
- Style application preserves attachment/tool settings and does not mutate saved defaults.
- Keyboard navigation, screen reader labels, dark mode, reduced motion, and large text.

Use focused `just fe-test test/...` during development, then `just fe-test`.

### End-to-end

Use the `e2e-testing` workflow on Linux:

1. open primary chat;
2. select a promoted subtopic and a broad parent topic;
3. send a turn and confirm discovery disappears;
4. verify Active context contents and Why included;
5. pin/remove/add a source and send another turn;
6. Fresh start without message deletion;
7. change model/style/effort and verify persistence after restart;
8. open a legacy thread, send a message, return to primary chat;
9. verify Threads search and original settings;
10. send a correction/rejection and verify the next turn no longer uses the superseded item;
11. send a new legacy-thread turn and verify its provisional topic/live context appears without waiting for consolidation;
12. trigger a test consolidation and verify the topic can merge/reparent without breaking selection;
13. simulate SSE disconnect and confirm detached completion recovery.

## 8. Performance, safety, and observability

- Cached topic discovery target: under 300 ms server time.
- Request-time compilation from a prepared pack/live delta: under 250 ms p95, with no LLM call.
- Real-time ingestion freshness: p95 under 5 seconds after an assistant turn commits; durable hourly catch-up remains the recovery guarantee.
- Consolidation freshness: every eligible dirty user's watermark advances within 75 minutes under normal load. Track queue age and apply bounded concurrency/backpressure rather than launching one model request per topic simultaneously.
- Cold bootstrap is the only normal path allowed to wait on a curator: prewarm on topic activation; cap first-turn wait at 12 seconds and measure fallback rate.
- Log event/context watermarks, pack/prompt/model versions, candidate/selected counts, validation failures, retry counts, token totals, active-topic confidence, queue age, cost, cache hits, and fallback use; never log full private message/memory content or curator prompts.
- Scope every topic/context query by authenticated user through the owning conversation.
- Treat conversation, assistant, tool, and KB text as untrusted context, not curator/system instructions; retain role boundaries, source delimiters, schema validation, and evidence-ID ownership checks.
- Do not silently send history to a cloud curator in local-only mode. Expose provider/model/privacy configuration and record the provider on each generated pack.
- Keep application context-pack caching independent of provider prompt caching. A provider cache miss or eviction changes cost/latency only, never results.
- Cap pinned material; warn before pins consume the dynamic-context budget.
- Context snapshot metadata stores identifiers/reasons, not duplicate full source content.
- Apply per-user consolidation quotas and fair scheduling so one very active account cannot starve others.
- If topic/context APIs fail, keep chat functional with valid pins/exclusions plus the recent-turn/raw-evidence fallback and surface a non-blocking limited-context state.

## 9. Documentation and release requirements

In the implementation PRs, update:

- `docs/api.md` for every new/changed endpoint and SSE type;
- `docs/database.md` for topic evidence/authority/status semantics, context versions/watermarks, exclusions, queue leases, and migrations;
- `docs/architecture.md` for the primary-chat, real-time ingestion, hourly consolidation, request-time compiler, provider capability/privacy, sidebar, and style flows;
- `backend/app/docs/help/` guides for topics, Active context, Threads, Fresh start, and response styles;
- `docs/environment.md` and `deploy/.env.example` for curator provider/model/thinking, local/cloud privacy mode, hourly interval, bootstrap timeout, concurrency, and rollout flags;
- English and Spanish ARB files for all user-facing strings.

Every phase ends with `just check` and its relevant full test suite. After merge to `main`, deploy, verify `just deploy-status`, then update only the report IDs delivered by that deployment.

## 10. Acceptance criteria

The feature is complete when:

- one primary chat works across restart and devices;
- personal topics are automatically derived from the user's real message/conversation history and discovery matches the approved line-free responsive mockup;
- promoted subtopics are visibly hierarchical and directly selectable;
- any parent topic can start a conversation;
- a new turn updates provisional topic membership/context within seconds, without waiting for hourly consolidation;
- the hourly job processes only dirty users, is retryable/idempotent across restarts/replicas, and advances materialized context packs through an explicit watermark;
- every promoted fact, decision, preference, constraint, deadline, and open loop is grounded in owned active evidence and follows the authority/temporal rules;
- explicit corrections and rejected/discarded ideas supersede or exclude prior state and cannot be silently reintroduced by retrieval or later consolidation;
- edits/deletes/restores invalidate affected context immediately, even before a new pack is generated;
- periodic evidence-first rebuilds demonstrate no accumulating summary drift;
- prepared topic turns compile without an LLM call, while cold first turns show preparation and have a bounded safe fallback;
- active context is visible, explainable, editable, and contains no Activity view;
- Fresh start removes active context without deleting history;
- legacy threads remain fully listable and selectable;
- style, model, system prompt, and supported thinking effort can be changed from the composer;
- all four normalized effort positions remain visible, while unsupported positions are disabled and can never be selected or persisted;
- every enabled normalized level maps deterministically to a tested provider-native reasoning value;
- context selection stays inside budget, isolates unrelated sibling topics, and has a safe pins/exclusions/recent-turn/raw-evidence fallback;
- the production curator wins the grounded-context evaluation and respects local/cloud privacy configuration;
- unit, widget, E2E, lint, analysis, and production health checks pass.
