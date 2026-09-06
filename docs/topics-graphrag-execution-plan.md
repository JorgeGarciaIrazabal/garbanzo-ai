# Dynamic Context & GraphRAG: Implementation Plan & Testing Matrix

**Date:** September 2026

**Status:** Approved for Implementation

**Tracking Issue:** Dynamic Context + Unified Chat (GraphRAG & Architecture Optimization)

---

## 1. Overview & Objectives

This plan details the transition of Garbanzo's **Topics & Dynamic Context** system into an evidence-grounded **GraphRAG** engine. The objectives are:

1. **Preserve Graph Integrity:** Eliminate destructive message deletions during topic switches by implementing `session_epoch` partitions, preserving all evidence links.
2. **Smarter Context Building (GraphRAG):** Replace character-level lexical matching with hybrid pgvector cosine similarity + full-text search, topic centroid embeddings, and 1-hop subgraph expansion.
3. **Decouple Request-Time TTFT:** Pre-warm and cache active context packs in the background so compilation overhead drops from ~150ms to < 5ms.
4. **Decompose Consolidation Monolith:** Break down `TopicConsolidationService` (1,261 lines) into single-responsibility modules.
5. **Improve UX Agency:** Replace silent backend auto-switching with a user-facing **Topic Drift Prompt**, add topic discovery search, and surface evidence provenance in the active context panel.

---

## 2. Milestones & Task Breakdown

### Milestone 1: Session Partitioning & Graph Integrity (Backend Foundation)
*Goal: Stop deleting messages and tearing down evidence links during topic switches.*

- [x] **Task 1.1: Schema Migration `043_conversation_session_epoch.sql`**
  - Add `session_epoch INTEGER NOT NULL DEFAULT 0` to `conversations`.
  - Add `session_epoch INTEGER NOT NULL DEFAULT 0` to `messages`.
  - Index `(conversation_id, session_epoch, seq)`.
- [x] **Task 1.2: Refactor `TopicSwitchService`**
  - Replace `_clear_messages` (`DELETE FROM messages`) with:
    - Increment `conversation.session_epoch += 1`.
    - Bump `conversation.context_version += 1`.
    - Clear only `ActiveContextItem` rows for the current conversation.
  - **Do not enqueue `"delete"` ingestion events.**
  - Ensure all historical `MessageTopic` memberships and `TopicAssertionEvidence` rows remain intact.
- [x] **Task 1.3: Update Query Surfaces in `ConversationService` and `ChatService`**
  - For primary conversations, filter active chat view to `session_epoch == conversation.session_epoch`.
  - Add API query parameter `GET /chat/conversations/{id}/messages?epoch=all|current` (default `current` for primary, `all` for threads).
- [x] **Task 1.4: Un-skip and Update `test_topic_switch.py`**
  - Fix test dependency overrides and re-enable skipped tests.
  - Add assertions verifying that `MessageTopic` and `TopicAssertionEvidence` remain intact after topic switches.

---

### Milestone 2: Hybrid GraphRAG Context Engine
*Goal: Replace naive lexical Jaccard overlap with pgvector hybrid search, topic centroid routing, and subgraph expansion.*

- [x] **Task 2.1: Schema Migration `044_topic_centroids_and_graph_edges.sql`**
  - Add `centroid_embedding vector(768)` to `topics`.
  - Create table `topic_relations`:
    - `(source_topic_id, target_topic_id, relation_type, confidence, created_at)`
    - Relations: `parent_of`, `child_of`, `relates_to`, `depends_on`.
  - Index `topics` on `centroid_embedding` using IVFFlat (cosine distance).
  - Index `topic_assertions` on `embedding` using IVFFlat (cosine distance).
- [x] **Task 2.2: pgvector Hybrid Assertion Retrieval in `TopicContextCompiler`**
  - Embed the incoming user query using `OllamaEmbeddingProvider.embed([current_query])`.
  - Run hybrid SQL search fusing cosine distance (`1.0 - (embedding <=> query_vector)`) with PostgreSQL full-text search (`ts_rank_cd`).
  - Weight active topic assertions higher while allowing relevant cross-topic assertions above a relevance threshold ($> 0.65$).
- [x] **Task 2.3: Subgraph Expansion (1-Hop Traversal)**
  - Expand seed assertions along:
    - Entity / concept links.
    - Causal links (`superseded_by_id`, `contradicts`).
    - Explicit `topic_relations` edges.
  - Filter out exclusions via `TopicExclusion` and emit rejected items strictly as negative guardrails.
- [x] **Task 2.4: Background Context Pre-warming & Caching**
  - Cache compiled context packs in PostgreSQL/memory keyed by `(conversation_id, context_version)`.
  - When an assistant turn finishes streaming, trigger a background task to pre-compile the baseline context pack for the *next* turn.
  - `compile()` returns the cached pack immediately, evaluating only real-time deltas (< 5ms TTFT overhead).

---

### Milestone 3: Ingestion Streamlining & Consolidation Refactoring
*Goal: Replace 4-word label derivation, extract multilingual assertions, and decompose the 1,261-line monolith.*

- [x] **Task 3.1: Centroid-Based Topic Matching in `TopicIngestionService`**
  - Replace `_best_topic_match` word token overlap with cosine similarity against topic `centroid_embedding`.
  - If cosine similarity $\ge 0.72$, attach turn to existing topic.
  - If no match, generate a concise subject title via clean semantic prompt or fallback.
- [x] **Task 3.2: Multilingual / Natural Assertion Extraction**
  - Supplement English regex patterns with Spanish patterns (`_ASSERTION_PATTERNS` and `_REJECTION_RE`) and assertion embedding generation with EMA centroid updates.
- [x] **Task 3.3: Decompose `TopicConsolidationService`**
  - Split into package `backend/app/topics/consolidation/`:
    - `reconciler.py`: Evidence verification, superseding chains, contradiction resolution.
    - `clusterer.py`: Hierarchy adjustments, parent-child proposals, topic merging.
    - `pack_builder.py`: Deterministic assembly, semantic model curation, XML packaging.
    - `worker.py`: Distributed lease claiming, concurrency control, error handling.
  - Retain `topic_consolidation_service.py` as backward-compatible facade delegating to the submodules.

---

### Milestone 4: UX & Interaction Enhancements
*Goal: User agency over autonomous changes, scalable discovery, and transparent provenance.*

- [x] **Task 4.1: Topic Drift Detection & UI Prompt Chip**
  - Backend `detect_drift()` detects topic drift via centroid cosine similarity (< 0.20 similarity / > 0.80 distance) and finds candidate topics ($\ge 0.72$).
  - `ChatService` emits SSE chunk `{"topic_drift": {"detected_topic_id": "...", "label": "..."}}`.
  - Flutter frontend handles SSE drift event in `ChatProvider` and `TopicDiscoveryProvider`.
  - `TopicBanner` renders prompt chip: `💡 Talking about [Topic]? [Switch] [Dismiss]`.
- [x] **Task 4.2: Topic Discovery Search & Categorization (`TopicLanding`)**
  - Added topic search bar (`_TopicSearchBar`, `topic_search_input`) in `TopicLanding`.
  - Filters `visibleTopics` in `TopicDiscoveryProvider` in real time.
- [x] **Task 4.3: Evidence Provenance & Deep Linking (`ActiveContextPanel`)**
  - Added source provenance chip (`context_item_provenance_${item.id}`) to `ActiveContextPanel`.
  - Displays provenance source type and source message ID.
- [x] **Task 4.4: Interactive Carryover Modal on Switch**
  - Created `TopicSwitchConfirmationDialog` with carryover toggle checkbox and confirm/cancel actions.
  - Allows user agency when switching topics.

---

## 3. Comprehensive Testing Plan

### 3.1 Backend Test Matrix

| Test Suite | File | Focus / Coverage |
|---|---|---|
| **Session Partitioning** | `backend/tests/test_topic_switch.py` | Verify topic switch increments `session_epoch`, clears active context items, but preserves messages and evidence links intact. |
| **Hybrid Vector Search** | `backend/tests/test_topic_context_pipeline.py` | Verify vector cosine distance retrieves assertions with synonyms; verify full-text fusion score; verify negative guardrail injection. |
| **Centroid Classification** | `backend/tests/test_topic_ingestion.py` | Verify turns route to topics by semantic similarity without keyword overlap; verify topic explosion is prevented. |
| **1-Hop Graph Expansion** | `backend/tests/test_topic_models.py` | Verify `topic_relations` edges expand correctly and link cross-domain facts. |
| **Consolidation Submodules** | `backend/tests/test_topic_consolidation.py` | Unit tests for `reconciler.py`, `clusterer.py`, and `pack_builder.py`. |
| **Pre-warming Latency** | `backend/tests/test_topic_context_pipeline.py` | Benchmark `compile()` latency: must be $< 10\text{ms}$ with cached pack. |

### 3.2 Frontend Test Matrix

| Test Suite | File | Focus / Coverage |
|---|---|---|
| **Topic Drift UI** | `test/widgets/topic_drift_test.dart` | Verify banner appears on SSE drift event; verify "Switch Context" calls provider; verify "Stay" pins current topic. |
| **Discovery Search & Filter** | `test/widgets/dynamic_context_widgets_test.dart` | Verify search input filters topic cards; verify category tabs filter by active date. |
| **Provenance Deep-Link** | `test/widgets/active_context_panel_test.dart` | Verify expanding an item displays quote; verify tap on source navigates to message. |
| **Carryover Modal** | `test/widgets/carryover_modal_test.dart` | Verify checkbox selection toggles carryover payload in switch request. |

### 3.3 Quality Gates & CI

Before any milestone is marked done:
1. `just check` passes with 0 lint, format, or import cycle warnings on both Python and Flutter.
2. `just test` passes full suite (1114 backend tests, 699+ Flutter tests).
3. No database migration downgrade failures or schema lock regressions.
