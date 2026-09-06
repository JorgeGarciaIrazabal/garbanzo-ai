# Topics & Dynamic Context: Architecture Audit, Optimizations & GraphRAG Strategy

**Date:** September 2026

**Status:** Design Proposal & Engineering Audit

**Scope:** `backend/app/topics/`, `lib/features/topics/`, database schemas, and integration with chat pipeline.

---

## 1. Executive Summary

The **Topics & Dynamic Context** feature transforms Garbanzo from a traditional "list of ephemeral chat threads" into a **unified primary chat** grounded in an evolving, evidence-backed personal knowledge graph. Users converse continuously in one thread while the system detects topics, tracks confirmed facts, decisions, constraints, deadlines, and open loops, and compiles a bounded active context for each turn.

### Current Implementation Assessment

| Component | Maturity | Core Strengths | Critical Gaps & Bottlenecks |
|---|---|---|---|
| **Data Models & Schema** (`038`–`042`) | **Strong (8.5/10)** | Grounded evidence links (`TopicAssertionEvidence`), temporal validity, immutable versioned packs, durable ingestion events. | Missing explicit graph edges between topics/entities; relies on simple single-parent hierarchy. |
| **Context Compiler** (`TopicContextCompiler`) | **Functional (5/10)** | Strict token budgeting, hard exclusion filtering, XML-wrapped injection. | **No vector search** (pgvector column is ignored); relies on Python word-overlap sets (`Jaccard >= 0.34`); synchronous DB queries in request path delay TTFT. |
| **Ingestion Pipeline** (`TopicIngestionService`) | **Brittle (4/10)** | Durable event queue; non-blocking detached ingestion tasks. | Hardcoded 5 English regexes (`"i decided"`, `"must"`); topic labeling takes the first 4 words of a message, causing massive topic fragmentation. |
| **Consolidation Service** (`TopicConsolidationService`) | **Overengineered (5/10)** | Strict evidence verification, lease-based worker concurrency. | **1,261-line monolith (52 KB)**; fragile JSON parsing hacks for LLM variants; slow, resource-heavy hourly batch runs. |
| **Topic Switch & Carryover** (`TopicSwitchService`) | **Hazardous (4/10)** | Single-call switch, snapshot archiving. | **Bug:** Synchronously executes `delete(Message)` on primary chat and triggers `"delete"` ingestion events that revoke derived evidence from the graph. |
| **Frontend UX** (`lib/features/topics/`) | **Polished (7.5/10)** | Faithful to design mockup, responsive mobile/desktop layout, clean breadcrumbs, split Active Context panel. | Missing search/filter in topic discovery; silent topic switching after 2 turns without user prompt; no provenance deep-linking. |

---

## 2. In-Depth Code-Level Audit of Current Implementation

### 2.1 Context Compilation (`TopicContextCompiler.py`)

The request-time compiler prepares `<topic_context>` right before calling the LLM provider.

#### Bottleneck 1: Lexical Word-Match Instead of Semantic Vector Search
In `_assertion_candidates` (lines 406–428):
```python
content_terms = self._terms(assertion.content)
query_match = len(query_terms & content_terms) / max(1, len(content_terms))
score = (
    0.35 * query_match
    + 0.20 * topic_affinity
    + 0.15 * authority_score * assertion.confidence
    + 0.10 * recency
    + 0.10 * query_match
    + 0.05 * importance
    + 0.05
)
```
- `TopicAssertion.embedding` is declared as `Vector(768)` in migration `039`, yet `_assertion_candidates` loads all active assertions into memory and performs character-level regex token matching.
- Synonyms, rephrasing, multilingual queries (e.g., Spanish, which the app supports), and semantic proximity fail completely. If a user asks *"How should I invest my retirement money?"* and an assertion is *"User allocates 80% to index funds and 20% to bonds"*, the lexical intersection is zero (`query_match = 0.0`).

#### Bottleneck 2: Synchronous Database Queries in the Critical Turn Path
In `ChatService._maybe_compile_topic_context`:
- On *every single user message*, before streaming a single token to the client, the backend executes 4–6 SQL queries:
  1. `SELECT topic`
  2. `SELECT exclusions`
  3. `SELECT topic_assertions JOIN evidence JOIN messages JOIN conversations`
  4. `SELECT raw evidence messages`
  5. `DELETE / INSERT active_context_items`
  6. `UPDATE conversation.context_version`
- This adds 60–250ms of database round-trip latency to the Time-To-First-Token (TTFT).

---

### 2.2 Ingestion & Classification (`TopicIngestionService.py`)

#### Problem 1: Primitive Label Derivation Causes Topic Explosion
In `_derive_label`:
```python
words = [
    word for word in re.findall(r"[\w-]+", text)
    if len(word) >= 3 and word.casefold() not in _STOP_WORDS
][:4]
return " ".join(words).strip().title()[:200] if words else "New topic"
```
If a user asks:
- *"Can we discuss my retirement plan?"* → creates Topic: **"Discuss Retirement Plan"**
- *"What are the tax implications on retirement?"* → zero keyword overlap with `"Discuss Retirement Plan"` (stop words stripped: `discuss`, `plan` vs `tax`, `implications`) → creates Topic: **"Tax Implications Retirement"**
- Within a few days, the user's graph contains dozens of fragmented, pseudo-duplicate topics instead of a consolidated topic `"Retirement Planning"` with subtopics.

#### Problem 2: Hardcoded English Regex Extraction
In `_ASSERTION_PATTERNS`:
Only 5 exact English regexes extract assertions in real-time (`"i decided"`, `"i prefer"`, `"must"`, `"my goal is"`, `"deadline"`). Normal descriptive statements like:
- *"I run macOS 15 on an M3 MacBook Pro"*
- *"Our production database is hosted on Neon"*
- *"Tengo una reunión mañana con el equipo de producto"* (Spanish)
are completely missed by the real-time path.

---

### 2.3 The Topic Switch Deletion Hazard (`TopicSwitchService.py`)

In `TopicSwitchService._clear_messages`:
```python
async def _clear_messages(self, conversation: Conversation) -> None:
    messages = list((await self.db.scalars(
        select(Message).where(Message.conversation_id == conversation.id)
    )).all())
    for message in messages:
        await enqueue_message_event(self.db, conversation, message, "delete")
    if messages:
        await self.db.execute(delete(Message).where(Message.conversation_id == conversation.id))
```
When `enqueue_message_event(..., "delete")` executes, `TopicIngestionService._revoke_message` runs:
```python
await self._remove_message_derivations(event.source_id)
```
This **deletes all `MessageTopic` memberships and all `TopicAssertionEvidence` rows** pointing to those message IDs!
Even though the raw JSON is saved in `TopicArchive`, the actual SQL foreign keys and evidence-graph edges in `topic_assertion_evidence` are severed! This contradicts the fundamental product invariant of durable, evidence-grounded knowledge.

---

### 2.4 Monolithic Complexity in `TopicConsolidationService.py`

At **1,261 lines**, `TopicConsolidationService.py` violates single-responsibility:
- Merges topic clustering, parent-child tree repair, assertion deduping, structured output parsing, JSON error recovery, database lease claiming, token budgeting, and fallback logic into one class.
- Makes unit testing brittle (as seen by the skipped tests in `test_topic_switch.py`).

---

## 3. Smarter Context Building: The GraphRAG Architecture

To solve topic fragmentation, missing semantic context, and cross-domain reasoning, we propose evolving the flat hierarchy into a **Dual-Layer GraphRAG Architecture**.

```
                         ┌───────────────────────────────┐
                         │      User Query / Message     │
                         └──────────────┬────────────────┘
                                        │
                                        ▼
                         ┌───────────────────────────────┐
                         │   Query Intent & Embedding    │
                         │ (Ollama nomic-embed-text 768) │
                         └──────────────┬────────────────┘
                                        │
                ┌───────────────────────┴───────────────────────┐
                ▼                                               ▼
┌───────────────────────────────┐               ┌───────────────────────────────┐
│     Level 1: Topic Graph      │               │   Level 2: Entity & Assertion │
│   (Communities & Domains)     │               │        Knowledge Graph        │
│                               │               │                               │
│  • Fast semantic matching to  │               │  • pgvector Cosine Search     │
│    topic centroids            │               │    (768-dim distance < 0.35)  │
│  • Ancestor & child scope     │               │  • Entity-Entity graph edges  │
│  • Community summaries        │               │    (e.g., PostgreSQL -> DB)   │
└───────────────┬───────────────┘               └───────────────┬───────────────┘
                │                                               │
                └───────────────────────┬───────────────────────┘
                                        │
                                        ▼
                         ┌───────────────────────────────┐
                         │ Subgraph Expansion & Rerank   │
                         │ • 1-hop neighbor expansion    │
                         │ • Temporal validity filtering │
                         │ • Negative guardrail filters  │
                         └──────────────┬────────────────┘
                                        │
                                        ▼
                         ┌───────────────────────────────┐
                         │ Linearized Context Synthesis  │
                         │ • Active Topic State          │
                         │ • Grounded Assertions         │
                         │ • Cross-Topic Relevant Facts  │
                         │ • Exact Evidence Spans        │
                         └───────────────────────────────┘
```

### 3.1 Dual-Layer Graph Representation

#### Layer 1: Topic Community Graph (Macro Level)
- Topics are not just single-parent nodes; they form an acyclic directed graph (DAG) with typed inter-topic relationships:
  - `parent_of` / `child_of` (taxonomy hierarchy: *Software Engineering → Garbanzo AI*)
  - `relates_to` (cross-domain correlation: *Tax Planning ↔ Real Estate Investment*)
  - `dependency_of` (workflow sequence: *Architecture Design → Implementation*)
- Each topic maintains a **centroid embedding** (average of its active assertions and message embeddings).
- Matching a message to a topic becomes a cosine similarity check against topic centroids:
  $$\text{sim}(Q, T) = \frac{\mathbf{e}_Q \cdot \mathbf{c}_T}{\|\mathbf{e}_Q\| \|\mathbf{c}_T\|}$$
  If $\max(\text{sim}) \ge 0.72$, route to existing topic; if between $0.50$ and $0.71$, suggest attachment; if $< 0.50$, create candidate.

#### Layer 2: Entity & Assertion Graph (Micro Level)
- Assertions (`TopicAssertion`) are linked to extracted Named Entities (`TopicEntity`):
  - E.g., `Assertion("Deploying Kokoro TTS in-process")` links to `Entity("Kokoro TTS")` and `Entity("FastAPI")`.
- When the user asks about *"audio performance"*, vector search retrieves the Kokoro TTS assertion even if the active topic is currently `"Server Configuration"`.
- Enables **cross-topic associative retrieval** without context pollution.

### 3.2 Hybrid Vector + Graph Search in PostgreSQL (pgvector)

Leverage pgvector and Postgres full-text search already present in the stack (just as `KnowledgeBaseService` does):

```sql
WITH semantic_matches AS (
    SELECT
        ta.id AS assertion_id,
        ta.topic_id,
        ta.content,
        ta.kind,
        ta.confidence,
        ta.authority,
        (1.0 - (ta.embedding <=> :query_vector)) AS semantic_score,
        ts_rank_cd(to_tsvector('english', ta.content), websearch_to_tsquery('english', :query_text)) AS lexical_score
    FROM topic_assertions ta
    JOIN topics t ON t.id = ta.topic_id
    WHERE t.user_id = :user_id
      AND ta.status = 'active'
      AND (ta.valid_until IS NULL OR ta.valid_until > NOW())
      AND (ta.valid_from IS NULL OR ta.valid_from <= NOW())
),
ranked_seeds AS (
    SELECT
        assertion_id,
        topic_id,
        content,
        kind,
        (0.70 * semantic_score + 0.30 * COALESCE(lexical_score, 0)) AS hybrid_score,
        CASE WHEN topic_id = :active_topic_id THEN 1.25 ELSE 1.0 END AS topic_boost
    FROM semantic_matches
    WHERE semantic_score > 0.45 OR lexical_score > 0.1
)
SELECT * FROM ranked_seeds
ORDER BY (hybrid_score * topic_boost) DESC
LIMIT 20;
```

### 3.3 Subgraph Expansion (1-Hop Traversal)
Starting from seed assertions:
1. Fetch all assertions that share an entity or are connected via `superseded_by_id` or `contradicts`.
2. Apply `TopicExclusion` hard filters: drop any assertion whose entity or concept is excluded.
3. If an assertion has status `rejected`, emit it into the prompt strictly as a negative guardrail:
   `Do not propose <option>; the user rejected it on <date>.`

### 3.4 In-Prompt Context Formatting

Format the assembled subgraph with clear structural semantics:

```xml
<topic_context active="Garbanzo AI Development" path="Engineering > Garbanzo AI">
  <!-- PRIMARY TOPIC STATE -->
  <topic_state>
    <goal>Build an evidence-grounded unified chat with dynamic context</goal>
    <constraints>
      <item id="c-1" authority="user_statement">Postgres runs only via Docker</item>
      <item id="c-2" authority="user_statement">All CLI commands must use 'just'</item>
    </constraints>
    <decisions>
      <item id="d-1" authority="user_statement">Use nomic-embed-text for 768-dim embeddings</item>
    </decisions>
  </topic_state>

  <!-- ASSOCIATED CROSS-TOPIC KNOWLEDGE (RELEVANT GRAPH NODES) -->
  <related_knowledge>
    <item topic="Local Infrastructure" relation="depends_on">Ollama runs locally on port 11434</item>
  </related_knowledge>

  <!-- NEGATIVE GUARDRAILS -->
  <guardrails>
    <avoid>Do not recommend running pytest or flutter directly without 'just'</avoid>
  </guardrails>
</topic_context>
```

---

## 4. Backend Workflow Optimizations

### 4.1 Asynchronous Pre-warming & Context Caching
- **The Problem:** Compiling context synchronously on every turn adds 150ms+ to TTFT.
- **The Fix:**
  1. Cache the compiled context pack in memory (or Redis/Postgres JSONB) keyed by `(conversation_id, context_version)`.
  2. While the assistant streams its response, asynchronously ingest the completed turn and pre-compile the *next* turn's baseline context pack.
  3. When the user sends their next message, simply inject the cached pack plus any real-time live delta. TTFT overhead drops to **< 5ms**.

### 4.2 Fix Topic Switching: Soft Sessions Instead of Hard Message Deletes
- **The Problem:** Deleting messages destroys evidence links.
- **The Fix:**
  - Introduce `conversation_turns` or a `session_epoch` integer column on `conversations`.
  - When switching topics:
    1. Bump `conversation.session_epoch += 1`.
    2. Mark the switch boundary with a synthetic system marker `Message(role="system", meta={"event": "topic_switch", "from_topic": A, "to_topic": B})`.
    3. The chat UI filters messages to show only `session_epoch == current` (or shows a collapsible divider `"Prior discussion in Topic A"`).
    4. **All `Message` rows remain permanently in PostgreSQL.**
    5. `MessageTopic` memberships and `TopicAssertionEvidence` foreign keys remain 100% valid and queryable!

### 4.3 Lightweight Real-Time Embedding Classification
- Instead of the fragile 4-word string slicing:
  1. Call `EmbeddingProvider.embed([message.content])` in the background ingestion worker.
  2. Perform a nearest-neighbor lookup against existing user topics.
  3. If similarity > 0.70, attach turn to topic.
  4. If no topic matches, generate a clean 2–4 word title using a small prompt or fast local heuristic.

### 4.4 Modularizing `TopicConsolidationService`
Decompose the 1,261-line class into four focused modules:

```
backend/app/topics/consolidation/
├── __init__.py
├── reconciler.py      # Validates evidence IDs, handles superseding/contradictions
├── clusterer.py       # Topic centroid recalculation, hierarchy & merge proposals
├── pack_builder.py    # Deterministic & model-assisted context pack compilation
└── worker.py          # Leased scheduled job orchestration & concurrency limits
```

---

## 5. UX & Interaction Design Improvements

### 5.1 Explicit Topic Drift Detection (User Agency over Autonomy)

Resolved (bug 1ba9a9f8): the silent 2-match auto-switch was removed entirely. Ingestion only seeds the active topic when none is set, and never redirects an existing user selection; topic changes are user-initiated (switch/combine/drift banner) only.

**Improved UX:**
- When the backend detects a topic shift with high confidence ($> 0.80$), emit an SSE event:
  `{"topic_drift": {"detected_topic_id": "uuid", "label": "Tax Strategy", "confidence": 0.88}}`
- The Flutter client shows an unobtrusive banner chip above the composer:
  ```
  💡 You seem to be discussing Tax Strategy now.
  [ Switch Context ]    [ Stay in Finance ]    [ ✕ ]
  ```
- If the user clicks **Switch Context**, a smooth topic switch triggers. If they dismiss or click Stay, the current topic is pinned.

### 5.2 Topic Discovery: Search, Filter, and Organization

The current organic floating bubble field looks sleek for 5–10 topics, but degrades when a user has 40+ topics.

**Enhancements:**
1. **Search & Quick Filter Bar:** Add a clean search input at the top of `TopicLanding` that filters topics in real-time.
2. **Category Tabs:** Group topics into:
   - **Recent:** Topics active in the last 7 days.
   - **Projects / Deep Context:** Topics with high mention counts and curated packs.
   - **Explore:** Suggested discovery paths.
3. **Contextual Menu:** Long-press or right-click on any topic button to:
   - Pin / Favorite
   - Rename
   - Merge with another topic
   - Archive

### 5.3 Active Context Provenance & Deep Linking

In the split `ActiveContextPanel`:
- Currently shows generic tags: `"Grounded fact"`, `"Recent topic evidence"`.
- **Improvement:** Make each context item expandable to reveal:
  - **Exact source quote:** The exact phrase spoken by the user.
  - **Timestamp & Conversation Link:** *"Confirmed Aug 24 in 'Budget Planning'"*.
  - **Jump to source:** Clicking scrolls to or opens the archived message.
  - **Direct Actions:** Single-click [Pin], [Exclude / Never use this], [Edit].

### 5.4 Interactive Carryover Selection

When switching topics or clicking "New Topic":
- Present a lightweight confirmation sheet:
  ```
  Switching to: Mobile App Redesign
  Carry over relevant context from Web Architecture?

  ☑ [Decision] Use Flutter for cross-platform clients
  ☑ [Constraint] Target response latency < 200ms
  ☐ [Open Loop] Review database migration scripts

  [ Switch & Apply (2 items) ]    [ Start Fresh ]
  ```
- Empowers the user to decide exactly what context crosses the boundary.

---

## 6. Implementation Roadmap

### Phase 1: Stability & Bug Fixes (Sprint 1)
- [ ] **Fix Message Deletion in Topic Switch:** Replace hard `DELETE FROM messages` with `session_epoch` soft partitions. Stop deleting evidence links.
- [ ] **Enable pgvector in `TopicContextCompiler`:** Implement vector cosine distance retrieval for `topic_assertions` alongside lexical matching.
- [ ] **Un-skip Topic Switch Tests:** Fix test environment overrides and reactivate `test_topic_switch.py`.

### Phase 2: Graph Enhancement & RAG Optimization (Sprint 2)
- [ ] **Topic Centroid Embeddings:** Add `centroid_embedding vector(768)` to `topics`. Update on message ingestion.
- [ ] **Hybrid Search Query:** Implement fused vector + full-text search in PostgreSQL for assertion candidates.
- [ ] **Context Pre-warming:** Asynchronously pre-compile context pack upon turn completion; cache for next turn.
- [ ] **Decompose Consolidation Monolith:** Split `topic_consolidation_service.py` into focused sub-modules.

### Phase 3: UX Polish & Interactive Controls (Sprint 3)
- [ ] **Topic Drift Prompt:** Add UI prompt chip when user strays from active topic.
- [ ] **Topic Discovery Search:** Add search bar and categorized view to `TopicLanding`.
- [ ] **Provenance Deep Linking:** Add source view and message navigation to `ActiveContextPanel`.
- [ ] **Interactive Carryover Sheet:** Provide selective checkbox modal on topic switch.

---

## 7. Verification & Acceptance Criteria

1. **Semantic Recall:** Queries without exact keyword matches (e.g. synonyms, conceptual queries) must retrieve relevant assertions with similarity $> 0.65$.
2. **Performance (TTFT):** Primary chat Time-To-First-Token must remain within 10% of legacy thread TTFT (compilation overhead $< 20\text{ms}$).
3. **Graph Integrity:** Switching topics 10 times consecutively must not reduce total historical assertion or evidence counts.
4. **Clean Codebase:** `TopicConsolidationService` modularized into files $< 400$ lines each, with full test coverage and `just check` green.
