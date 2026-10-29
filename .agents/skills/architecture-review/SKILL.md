---
name: architecture-review
description: Review Garbanzo AI architecture, simplification opportunities and maintainability with code evidence and prioritized follow-up proposals. Use for periodic code health reviews or a focused architectural review, rather than ordinary diff review.
---

# Architecture and maintainability review

Help the next feature or bug fix require fewer concepts, fewer coordinated edits
and clearer ownership. Review the code as it exists; recommend the smallest
change that produces a concrete improvement. A review request authorizes
inspection and a report. Implement changes only when the user asks for them.

## Establish the scope

- Read root `AGENTS.md`, `docs/architecture.md` sections for the selected flows,
  and their scoped `AGENTS.md` files. Read `docs/ai-workflow-guide.md` for task
  priorities and delivery gates. Architecture/design uses Astra under the
  repository model policy; record the actual model and surface unavailable
  required models instead of silently substituting one.
- Record the date, `git rev-parse HEAD`, worktree status and included local edits.
  Findings involving uncommitted code must say so; HEAD alone cannot identify it.
  Preserve unrelated edits and use `just` for tooling and verification.
- For a periodic review, read the latest completed report in
  `.ai/local/architecture-reviews/`, if present. Inspect changes since its source
  revision, existing findings and relevant open tasks using `just ai-task summary`
  and targeted `show` calls. Inspect the full task list only when deduplication
  needs it. If there is no usable previous revision, use roughly two weeks of
  Git history and label this as an initial baseline.
- Combine recent churn and repeated fixes with a rotating deeper review of one
  or two feature flows. Choose areas with cross-feature dependencies, duplicated
  policy or difficult tests. Follow an actual operation from UI through transport,
  business logic and persistence; include error and cancellation paths. Rotate
  into quieter areas on later reviews. State what was sampled and what remains
  unreviewed; a sampled review cannot certify the whole repository.

## Find changes that make iteration easier

Use `rg` for exact searches and the `code-navigation` skill for Python/Dart
symbols and callers. Exclude generated files, dependencies and build caches from
hotspot rankings, while keeping generated declarations available to analyzers.
File size, churn and complexity are investigation signals, not findings alone.

Assess the selected flows through these lenses:

| Lens | Evidence to look for | Useful simplification |
|---|---|---|
| Responsibilities and dependencies | Cycles, import-order constraints, transport code owning business policy, features reaching into each other's internals | Move a responsibility to its existing owner; expose a narrow boundary only where callers need it |
| Change propagation | One rule repeated across services, endpoints, widgets or tests; a routine feature needing many coordinated edits | Centralize the shared rule while preserving legitimate differences |
| State and lifecycle | Multiple sources of truth, unclear session/transaction ownership, hidden global mutation, stream/subscription/task cleanup spread across layers | Give state and resource lifetime an explicit owner |
| Contracts and failures | Repeated event parsing, mismatched API/model assumptions, broad exception handling, errors converted to success, configuration hidden by defaults | Make contracts and failure paths explicit at the appropriate boundary |
| Abstractions and obsolete paths | Pass-through layers, single-use general frameworks, unused registration or compatibility paths, flags with no live purpose | Inline or remove proven unnecessary machinery; keep abstractions that express a real contract |
| Testability and navigation | Extensive patching of internals, order-dependent setup, tests coupled to method structure, domain rules hidden in large providers/widgets | Isolate the domain decision and verify observable behavior through a stable boundary |

For each candidate, trace definitions, callers, registrations and relevant tests.
Look for counterexamples that justify the current design. Search absence alone
does not prove dead code: check dynamic tool/provider registration, routes,
scheduled jobs, platform entrypoints and persisted compatibility needs.

Evaluate proposals against the scoped invariants. In particular, preserve user
ownership checks, transaction boundaries, detached generation/workflow lifetimes,
originating conversation epochs, SSE/WebSocket contracts, Provider state
ownership and supported platform behavior. Refer to the owning docs for details.
Do not simplify by swallowing errors, removing required validation, or coupling
background work back to a request. Keep behavior changes explicit and separate
from a proposed behavior-preserving refactor.

Prefer deletion, consolidation or extraction into an existing feature boundary
when these reduce the effort of a concrete next change. Adding a new layer,
dependency, framework or generalized API needs evidence that its benefit exceeds
its maintenance cost. Neither fewer lines nor more indirection is a goal by
itself. Explain why retaining the current design is reasonable when appropriate.

## Deliver a useful review

Save a dated report under `.ai/local/architecture-reviews/` with a unique filename
so previous reviews remain available. Include:

- Source revision, local-edit scope, actual reviewer model, comparison baseline,
  inspected flows and areas left unreviewed.
- A short ranked list of actionable findings; prefer roughly three to five
  worthwhile items over an exhaustive style backlog. Zero findings is valid.
- For each finding: exact `path:line`/symbol evidence and callers, the maintenance
  problem, a concrete feature/fix made harder today, the smallest proposed change,
  expected benefit, effort (small/medium/large), regression risk, confidence,
  behavior to preserve, and acceptance criteria with relevant `just` checks.
  Distinguish observed problems from hypotheses needing investigation.
- Prior findings that are resolved, still present, or deferred with a reason.
  Recheck their code before carrying them forward; do not duplicate tasks.
- The next suggested focus and next review date, normally 14 days later.

Rank by demonstrated impact and likely benefit relative to effort and risk.
Maintenance is normally P3; a reproduced defect can justify P2 or higher under
the existing priority definitions. Do not inflate severity to promote a refactor.

Give the user the report link and the highest-value next action. State which
claims were statically inspected, tested, or left unverified. A report-only run
does not need full application tests; use focused checks if a claim needs them,
and report unavailable verification honestly.

When the user requests tracked follow-ups, create or update deduplicated Beads
tasks through `just ai-task`, linking the source revision, finding and acceptance
criteria. Do not edit generated `TASKS.md`. When implementation is requested,
use `guided-development` and `testing` for small behavior-preserving batches.

## Cadence

Suggest a review every two weeks, and after substantial changes to shared state,
transport, persistence or provider boundaries. The skill itself does not schedule
execution. If automatic runs are requested, agree on their scope and schedule
through the available scheduling workflow; keep review and implementation
authorization distinct.
