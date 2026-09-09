# Topics: pre-launch review and simplification plan

Reviewed September 5, 2026 against the working tree and implemented through
September 8, 2026. Recommendations assume no deployed Topics clients or feature
data to preserve.

## Implementation status

The launch-blocking contract and eligibility work is implemented in the current
working tree:

- Topic changes use one transaction-owned, row-serialized switch endpoint with
  required idempotency keys and committed-response replay.
- Generated carryover and the obsolete activation/prepare endpoints are removed.
  Users can explicitly retain pinned sources, and the compiler validates them
  again on every turn.
- The compiler uses one eligibility policy for pinned and dynamic assertions,
  messages, threads, memories, and knowledge sources. Invalid, deleted, expired,
  superseded, or excluded sources do not enter the prompt or inspection summary.
- Active-context edits and topic pin changes lock the primary conversation row
  and require its current context version, preventing stale writes from crossing
  a switch boundary.
- Archives store session metadata while original epoch-tagged messages remain the
  authoritative history.
- Retrieval is bounded before evidence expansion and the final rendered block
  obeys the configured token budget, including required guardrails and pins.
  PostgreSQL vector/FTS failures surface instead of quietly taking the
  SQLite-only test fallback. The migration smoke test executes a real
  768-dimensional pgvector + English FTS query.
- Prepared topic prompts now contain validated curated assertions and newer
  grounded assertion deltas; raw transcripts are used only for a cold topic
  that has no eligible assertion. The background graph curator fairly allocates
  a payload-size budget across topics from a higher bounded candidate scan, so
  the former 24-message request cap no longer defines the topic's knowledge.
- Flutter uses the server tree and authoritative switch result, searches nested
  topics with parent paths, reuses idempotency keys after recoverable failures,
  clears stale drift proposals, cancels the old client stream at a switch, and
  localizes switch/readiness text in English and Spanish. The bare chat route
  stays on the topic landing page while the primary conversation loads; server
  selection synchronization cannot redirect it into an old active topic. Topic
  selection and starter prompts stay in the primary conversation and use the
  switch contract.
- Parent topics are directly selectable while a separate control opens their
  children. The primary composer no longer creates a second conversation after
  topic selection. Parent compilation includes descendant assertions, and child
  compilation retains ancestor assertions during query reranking.
- The context panel shows grounded source excerpts, dates, and links to ordinary
  source threads. Adding a source uses a recent-message picker instead of a raw
  ID field, and earlier topic sessions reopen in a read-only paged viewer. Topic
  switching also materializes an eligible, bounded baseline working set so the
  pre-turn preview and token meter do not incorrectly show an evidence-backed
  topic as empty.

Focused automated verification covers switch replay and key conflicts, archive
metadata, pin retention/removal, source eligibility invalidation, the actual
provider input, exact compiler budgeting, strict Flutter contracts, nested
search, selection state, source UX, stale-stream isolation, and topic widgets.
The PostgreSQL migration smoke covers all 46 migrations, the hybrid query,
serialized competing switches, and preservation of a detached turn's captured
session epoch. `just ai-topics-retrieval-eval` runs the configured embedding
model against separate English and Spanish paraphrase, negation, correction,
and neutral-query cases; the September 8 local run achieved recall@1, recall@3,
and MRR of 1.0 for both languages.
Remaining launch evidence is listed below; this document does not claim
production latency or visual certification.

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

**Status (September 8): resolved by simplification.** Generated carryover and its
source type were removed. A switch optionally retains explicit pins, and each
retained reference passes the shared eligibility policy before prompt rendering.

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

Sources: [switch service](../backend/app/topics/topic_switch_service.py) and
[compiler](../backend/app/topics/topic_context_compiler.py).

### 2. Apply one eligibility policy to every context source

**Status (September 8): implemented and covered by focused regression tests.**

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

**Status (September 8): implemented and covered on PostgreSQL.** The migration
smoke races two switch transactions against one primary conversation and proves
they commit as distinct ordered boundaries. It also keeps a turn transaction
open across both switches and proves its later message write retains the epoch
captured when the turn began. Flutter widget coverage rejects late chunks and
reloads from the canceled client stream after a committed switch.

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

1. **Measure real text turns.** The empty-query in-process prewarm cache and its
   sub-10ms test are removed. Establish compiler p50/p95 using real user text on
   the intended PostgreSQL deployment before setting a launch target.
2. **Bound database work before materializing candidates.** The compiler now
   takes a bounded assertion seed set, prioritizes the validated pack and explicit
   pins, expands live evidence for those seeds, reserves raw messages for the
   no-assertion fallback, and caps documents and relation expansion,
   limits hybrid scores to the top 48, and trims the fully rendered context to
   its token budget. Capture PostgreSQL query plans and real data distributions
   before further tuning.
3. **Evaluate English and Spanish separately.** The PostgreSQL lexical component
   still uses `english`, while the configured semantic embedding path supplies
   multilingual recall. `just ai-topics-retrieval-eval` now measures the two
   languages separately over paraphrases, negations, corrections, and queries
   with no explicit fact pattern. The initial four-case set for each language
   ranked the expected evidence first in every case. Grow the checked-in fixture
   with anonymized failures as real usage reveals harder vocabulary.
4. **Test the production database path.** `just ai-migration-smoke` now inserts a
   768-dimensional vector and executes the vector + English FTS fused ranking on
   Docker PostgreSQL. Promote this smoke assertion into a repeatable CI gate when
   CI provides PostgreSQL + pgvector.

Measure context relevance, excluded-source leakage, topic fragmentation, compiler
p50/p95 latency, embedding/curator calls, and ingestion backlog. Set latency targets
from a baseline on the intended deployment, not empty-query microbenchmarks.

Sources: [compiler](../backend/app/topics/topic_context_compiler.py),
[pipeline tests](../backend/tests/test_topic_context_pipeline.py),
[ingestion](../backend/app/topics/topic_ingestion_service.py), and the
[bilingual evaluation](../scripts/ai_dev/topics_retrieval_eval.py) with its
[checked-in fixture](../scripts/ai_dev/fixtures/topics_retrieval_eval.json).

## Make the UI easier to understand

- **Search the entire topic tree.** Implemented: matching descendants retain
  their parent path. Keyboard navigation, narrow screens, and a large real topic
  set still need browser E2E validation.
- **Fix selection state before visual polish.** Implemented: loads retain their
  requested mode, free-text selection uses the authoritative server topic, and
  switch failures remain recoverable with stable idempotency keys. The ordinary
  topic landing and starter paths keep using the primary conversation, while a
  committed switch cancels the old client stream and installs the returned
  topic, epoch, and context version before the UI can reload stale state.
- **Show useful sources.** Implemented: the context panel resolves a grounded
  excerpt, source date and label, and navigation when the source belongs to an
  ordinary thread. Adding a source uses a picker over recent visible messages.
- **Make boundaries predictable.** Switch copy explains the new visible session,
  archives preserve the prior epoch, and stale drift proposals are discarded.
  Earlier primary-chat epochs reopen in a read-only paged viewer; ordinary
  source threads can also be opened from the context panel.
- **Finish localization.** Switch, drift, source, and readiness text now uses the
  English/Spanish ARB workflow. A complete Topics-screen localization audit is
  still useful because older panel labels predate this review.

Sources: [provider](../lib/features/topics/providers/topic_discovery_provider.dart),
[context panel](../lib/features/topics/widgets/active_context_panel.dart),
[switch dialog](../lib/features/topics/widgets/topic_switch_dialog.dart),
[banner](../lib/features/chat/widgets/topic_banner.dart).

## Suggested order

1. Fix eligibility and carryover; unify switch semantics and transaction handling.
2. Remove compatibility adapters, synthetic hierarchy, and duplicate preparation.
3. Keep curated packs and grounded assertion deltas as the prepared-topic
   representation; keep raw messages only as an explicit pin or cold-topic fallback.
4. Keep the real-query PostgreSQL smoke and bilingual retrieval fixture in the
   pre-launch gate; extend the fixture when retrieval failures are found.
5. Finish source navigation, global search, readiness/error states, and localization.

Architecture, API, database, and in-app help documentation now describe the
implemented switch, archive, compiler, and readiness behavior. The archive flow
has also been exercised end to end on the Linux desktop target, including a real
switch, archive listing, and opening the read-only session. Before launch, finish
the real-turn latency baseline and browser E2E pass described above.
