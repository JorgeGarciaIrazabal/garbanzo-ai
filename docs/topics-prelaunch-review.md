# Topics: pre-launch review and simplification plan

Reviewed September 5, 2026 against the current working tree, including uncommitted
implementation. This is a quick static code review, not a runtime, visual, or
performance certification. No tests or benchmarks were run for this document.
Recommendations assume no deployed Topics clients or data to preserve.

## Assessment

The feature has a useful core: keep related knowledge available without making
users manage a new thread for every subject, and let users inspect and control
what the assistant remembers. Evidence links, durable ingestion, explicit drift
suggestions, and session boundaries are good foundations.

The main weakness is the number of overlapping mechanisms: activation versus
switching, messages versus archive copies, curated packs versus live compilation,
and server hierarchy versus client-invented groups. These make behavior harder to
explain and leave gaps between what the UI promises and what the model receives.

**Recommendation: fix context correctness and unify switching before adding more
graph features.** Ship a small, predictable topic system, then justify additional
retrieval machinery with measured quality improvements.

### What is already implemented

The older [architecture review](topics-architecture-optimizations-and-rag-graph.md)
describes a previous implementation. Current code already has:

- Session epochs that preserve messages and evidence when switching topics.
- Vector/FTS scoring, centroid matching, and topic relation traversal.
- Extractor patterns for English and Spanish.
- Consolidation submodules, discovery search, and a visible drift proposal.

Do not repeat those items as missing features. Their effectiveness still needs
validation; the checked boxes in the [execution plan](topics-graphrag-execution-plan.md)
do not establish end-to-end correctness or latency.

## Fix before launch

### 1. Make carryover actually reach the next model turn

**Observed:** `TopicSwitchService._seed_carryover` writes `source_type="carryover"`
items with `state="dynamic"`. The compiler selects pins, assertions, and raw
evidence; it does not select those carryover items. `_sync_dynamic_items` then
replaces dynamic rows with its selected candidates. `_source_content` also has no
carryover resolver, so simply pinning an item does not solve this.

**Impact:** the switch response can show carried context that is absent from the
next prompt. Independent retrieval might rediscover the original message, but
that does not fulfill the carryover contract.

**Change:** preferably remove the separate carryover extractor for v1. Let users
explicitly retain existing, validated source references across the switch. If
generated carryover stays, integrate it into compilation with source validation,
exclusion checks, expiry, and a token budget. The extractor currently validates
JSON shape but does not verify returned message IDs against the archive; its
exception fallback also returns before `_cap` applies the token budget.

**Acceptance:** switch with a distinctive retained fact, send a real message, and
inspect the provider input. The fact must be present; excluded or unselected facts
must be absent. Reject fabricated source IDs and enforce the budget on failures.

Sources: [switch service](../backend/app/topics/topic_switch_service.py),
[extractor](../backend/app/topics/carryover_extractor.py),
[compiler](../backend/app/topics/topic_context_compiler.py).

### 2. Apply one eligibility policy to every context source

**Observed:** ordinary assertion candidates check validity windows, status,
superseding relationships, and concept exclusions. Pinned assertion resolution
checks assertion ownership but does not repeat those checks or require live
evidence. `_pinned_candidates` filters some excluded IDs, but not the complete
policy used for dynamic candidates.

**Impact:** pinning can retain an expired or superseded fact after ordinary
retrieval would stop using it.

**Change:** centralize source eligibility and use it for pins, live retrieval,
packs, carryover, and any cache. Pinning should influence priority, never override
deletion, exclusion, evidence validity, or a correction. Define precisely whether
“Remove” means next-turn omission, topic-scoped exclusion, or permanent forgetting.

**Acceptance:** pin a fact, then expire, supersede, exclude, or delete its evidence;
verify the next provider request omits it through every retrieval path.

Source: [compiler](../backend/app/topics/topic_context_compiler.py), especially
`_assertion_candidates`, `_pinned_candidates`, and `_source_content`.

### 3. Use one switch operation with one transaction owner

**Observed:** the frontend catches any switch failure and falls back to the older
activate endpoint, which does not advance the session epoch. The switch service
calls activation, whose `_bump_and_refresh` commits before the switch finishes.
Carryover and preparation can commit again. Despite the “async” comment, switch
awaits `prepare`, which awaits consolidation and can call the curator.

**Impact:** a failed or timed-out request can have already changed state; the
fallback can produce different session behavior. Switching can also wait for LLM
work. Activation can request another preparation from the client afterward.

**Change:** remove the client fallback and obsolete activation contract. Validate
the target first; atomically advance the session and set the topic; enqueue
preparation for a worker. Return the authoritative topic, epoch, and readiness.
Give switch retries an idempotency key and serialize competing session changes.
Helpers should flush; the orchestration should own the commit.

**Acceptance:** double-clicks and retries create one boundary. Test response loss
after commit, concurrent switches, switching during a streaming turn, and worker
failure. Old-turn writes/events must remain associated with their original epoch.

Sources: [topic service](../backend/app/topics/topic_service.py),
[switch service](../backend/app/topics/topic_switch_service.py),
[discovery provider](../lib/features/topics/providers/topic_discovery_provider.dart).

## Simplify the architecture

| Area | Recommended first-release choice | Reason |
|---|---|---|
| Session history | Keep messages with epochs; store small session metadata referencing them | `TopicArchive` currently copies message content and metadata even though originals survive. Avoid duplicate history and deletion semantics. |
| Hierarchy | One server-owned tree using `parent_id`; optional related-topic edges later | Remove `_presentationHierarchy` and synthetic `presentation:` IDs. Selecting a display group currently creates a real topic from its label. |
| Context building | One compiler with bounded retrieval and one shared eligibility policy | `_compile_primary` renders selected candidates; it reads the latest pack afterward for metadata rather than rendering that pack. Decide what packs contribute before maintaining both representations. |
| Background processing | Retain durable events and lease-protected processing; one preparation path | These protect recovery. Remove duplicate request/client-triggered preparation rather than removing durability. |
| Contracts | One strict response shape and one authoritative selection result | Remove list/items/topics response fallbacks and provisional IDs after success. No old deployed client needs those adapters. |
| Migrations | Consolidate only the undeployed feature migrations into a coherent initial schema | Preserve existing application data and deployed migrations. Treat resetting local feature data as an explicit implementation choice. |

Keep topic ownership, provenance, hard exclusions, and immutable turn snapshots.
Defer entity graphs, more relationship types, and extra discovery categories until
a small evaluation set demonstrates a need.

## Retrieval and performance improvements

1. **Measure real text turns.** `compile` reads the prewarm cache only when
   `current_query` is empty. The existing sub-10ms test also uses an empty query.
   This does not demonstrate faster normal chat. Start without the extra cache,
   or explicitly reuse validated baseline candidates and rerank with the query.
   Any retained cache needs freshness across workers, exclusions, and pack changes.
2. **Bound database work before materializing candidates.** `_assertion_candidates`
   loads all in-scope evidence rows, then runs a second hybrid scoring query with
   no top-k limit. Fetch bounded ranked seeds, expand within a fixed budget, and
   batch-load evidence. Measure actual PostgreSQL query plans before claiming
   vector indexes improve this path.
3. **Evaluate English and Spanish separately.** FTS currently uses `english`.
   Additional regex patterns alone do not establish multilingual recall. Use
   paraphrases, negations, corrections, and messages with no explicit fact pattern.
4. **Test the production database path.** Existing backend test fixtures use
   SQLite and scoring can fall back after SQL failure. Add Docker PostgreSQL +
   pgvector integration coverage that proves hybrid SQL actually executed.

Measure context relevance, excluded-source leakage, topic fragmentation, compiler
p50/p95 latency, embedding/curator calls, and ingestion backlog. Set latency targets
from a baseline on the intended deployment, not empty-query microbenchmarks.

Sources: [compiler](../backend/app/topics/topic_context_compiler.py),
[pipeline tests](../backend/tests/test_topic_context_pipeline.py),
[ingestion](../backend/app/topics/topic_ingestion_service.py).

## Make the UI easier to understand

- **Search the entire topic tree.** `visibleTopics` filters only the currently
  visible level. Show matching descendants with their parent path. Offer a simple
  recent-topic list alongside the map, and check keyboard navigation and narrow
  screens with a large topic set.
- **Fix selection state before visual polish.** Capture the requested mode before
  awaiting `load`: changing modes while loading can store a response under the
  wrong `_mode`. Apply the server result in `activateFreeText`, which currently
  leaves its provisional selection ID. Use one switch state machine with pending,
  success, and recoverable failure states; do not assume context is ready.
- **Show useful sources.** The context panel currently displays a source type and
  truncated ID. Provide the quote, date, and a navigable source. Replace the “add
  source” raw message-ID field with a source picker.
- **Make boundaries predictable.** Explain that changing topics starts a new
  visible session while preserving earlier discussion. Provide an obvious way to
  reopen it. Keep drift suggestions optional and discard stale proposals after
  manual selection or session changes.
- **Finish localization.** Switch-dialog and drift-banner strings include
  hardcoded English. Move them into the existing English/Spanish ARB workflow.

Sources: [provider](../lib/features/topics/providers/topic_discovery_provider.dart),
[context panel](../lib/features/topics/widgets/active_context_panel.dart),
[switch dialog](../lib/features/topics/widgets/topic_switch_dialog.dart),
[banner](../lib/features/chat/widgets/topic_banner.dart).

## Suggested order

1. Fix eligibility and carryover; unify switch semantics and transaction handling.
2. Remove compatibility adapters, synthetic hierarchy, and duplicate preparation.
3. Choose one history representation and clarify the role of curated packs.
4. Add real-query PostgreSQL tests and a small bilingual retrieval evaluation.
5. Finish source navigation, global search, readiness/error states, and localization.

Update the architecture, API, database, and in-app help alongside implementation.
In particular, replace the current description of switch preparation as an async
kickoff and qualify cache latency claims. No implementation changes are included
in this review.
