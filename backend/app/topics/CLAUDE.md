# Dynamic Context Topics — Agent Context

This package owns the user-scoped topic graph and the primary-chat dynamic
context pipeline. Import it through `app.topics.*`; do not recreate topic
models, schemas, services, jobs, or API routes under the generic packages.

## Layout and entry points

- `models.py` — graph, assertion, ingestion, immutable context, and active-context ORM models.
- `schemas.py` / `active_context_schemas.py` — API contracts.
- `api.py` — `/chat` topic/context endpoints; registered in `app.api.v1.router`.
- `topic_ingestion_service.py` — durable events, multilingual extraction, and centroid-based topic routing.
- `topic_consolidation_service.py` — backward-compatible facade delegating to `consolidation/` submodules:
  - `consolidation/reconciler.py` — evidence grounding, superseding chains, contradiction resolution.
  - `consolidation/clusterer.py` — hierarchy adjustment, parent-child clustering, safe topic merging.
  - `consolidation/pack_builder.py` — deterministic pack assembly and immutable context version creation.
  - `consolidation/worker.py` — distributed lease claiming, concurrency control, failure backoff.
- `topic_semantic_curator.py` — LLM-driven graph synthesis and curation.
- `topic_context_compiler.py` — hybrid vector + FTS retrieval, 1-hop graph expansion, pre-warming, and topic drift detection.
- `active_context_service.py` — user pins, exclusions, and optimistic context updates.
- `jobs.py` — scheduler entry point for hourly dirty-user consolidation.

## Invariants

- Every read and mutation is user-scoped; evidence, exclusions, and context packs must never cross users.
- Rejected/excluded material is a hard filter and must never be resurrected by a graph rebuild or fallback.
- The server graph is authoritative. The client may use only a conservative, presentation-only hierarchy fallback when a legacy flat result must be displayed.
- Topic context applies only to the primary conversation. Old conversations remain independent threads and must remain selectable from the Threads UI.
- Ingestion is durable before best-effort realtime work. Consolidation is idempotent, lease-protected, validates LLM output strictly, and promotes a complete immutable version atomically.
- Model output is untrusted data: preserve provenance, validate schema and ownership, and compile historical content as delimited data rather than instructions.

## Intentional exceptions

- SQL migrations remain in `backend/migrations/` and are never moved.
- In-app help remains at `app/docs/help/topics.md` because the help loader discovers that directory.

## Change checklist

Run the focused backend tests with `just be-test tests/test_topic_models.py tests/test_dynamic_context_contracts.py tests/test_dynamic_context_endpoints.py tests/test_topic_context_pipeline.py tests/test_scheduler.py`, then `just be-lint`. Update `docs/api.md`, `docs/architecture.md`, `docs/database.md`, `docs/environment.md`, and `app/docs/help/topics.md` whenever their respective contracts change.
