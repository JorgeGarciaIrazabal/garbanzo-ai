# Using the AI development workflow

This guide covers the normal day-to-day workflow: describe work to Codex, keep
priorities and dependencies in Beads, test a fixed preview, and explicitly
request a deployment when you are ready. For controller internals and recovery
details, see [Codex-first development](ai-development.md).

## The quickest way to work

Start a development session from the repository:

```bash
just ai "Add the feature described in my next message"
```

Inside an existing Codex session, speak naturally. You do not need to translate
requests into controller commands. Useful examples are:

- "Show me the highest-priority tasks that are ready, and recommend the next one."
- "Make the login failure P1 and put the settings redesign behind it."
- "Implement `garbanzo-abcd`. Give me a stable preview when it is ready."
- "I tested preview `chat-fix`. The retry button still duplicates the message."
- "Triage new production reports, but do not deploy anything."
- "Deploy the accepted changes."

Codex records implementation requirements and acceptance criteria in Beads and
keeps one agent on the work by default. It uses Terra for routine implementation,
Luna for narrow exploration, and Sol for substantive review. It delegates only
substantial independent tasks, using compact briefs rather than full conversation
history. A deployment happens only when you explicitly request it.

## Capture and prioritize work

Every implementable item should have a concrete description and observable
acceptance criteria. Create one directly when you already know the scope:

```bash
just ai-task create "Fix duplicate streamed messages" \
  --description "Retrying a failed stream can append the same assistant message twice." \
  --acceptance "One retry produces one persisted assistant message and the regression test passes." \
  --priority 1
```

Priorities use smaller numbers for more urgent work:

| Priority | Use it for |
|---|---|
| **P0** | Active outage, exploitable security problem, data loss, or data corruption |
| **P1** | Blocked core flow, serious production regression, or urgent user report |
| **P2** | Normal feature work and confirmed defects with a practical workaround |
| **P3** | Maintenance, test improvements, documentation, and low-impact polish |
| **P4** | Ideas and deliberately deferred work |

Update the scope or priority without changing the task ID:

```bash
just ai-task update garbanzo-abcd \
  --description "Updated scope after reproduction" \
  --acceptance "Updated observable result" \
  --priority 0
```

Use dependencies to express ordering. The first task cannot become ready until
the second task is complete:

```bash
just ai-task depend garbanzo-frontend garbanzo-backend
```

Review the queue with:

```bash
just ai-task summary --limit 10  # Compact recommendation for conversational task selection
just ai-task ready               # Full unblocked JSON
just ai-task list                # Full backlog JSON
```

For “list tasks,” “what should we work on,” or “recommend a task,” start with
`just ai-task summary`. It queries Beads directly, groups production reports and
dependency findings, and returns a bounded list of candidates selected from
Beads’ ready contract. In-progress tasks may be counted but are not recommended
by Beads. Run
the full `ready` or `list` output only when you explicitly need an exhaustive
inventory, and use `just ai-task show <id>` for the shortlisted IDs. Add
`--include-reports` or `--include-findings` when those groups should participate
in the recommendation.

When choosing between tasks at the same priority, prefer confirmed and
reproducible work, then work that unblocks other tasks, then the smaller item.
Keep report counts separate from impact: many duplicates can describe one minor
problem, while one report can identify a data-integrity failure.

## Choose a delivery path

For most work, tell Codex which task or outcome you want. The current agent works
in the main copy, runs checks appropriate to the change, and preserves unrelated
edits while you test and give feedback.

`just ai-run direct` is an optional way to record a bounded controller or workflow
change with declared files and commands:

```bash
just ai-run direct garbanzo-abcd \
  --owned scripts/ai_dev/example.py \
  --owned scripts/ai_dev/tests/test_example.py \
  --command 'just ai-test' \
  --command 'just ai-lint' \
  --command 'just check'
```

This command is useful when its recorded evidence and strict file accounting add
value. It is optional; trusted local work does not require a separate
self-certification run.

Use an isolated worker or parallel batch only for substantial tasks that can
proceed independently and whose owned files do not overlap:

```bash
just ai-batch garbanzo-abcd garbanzo-efgh
```

The coordinator permits up to three workers, subject to machine and provider
capacity. Each worker receives a compact self-contained brief instead of full
conversation history, operates on a fixed source snapshot, and returns a patch.
Only the coordinator integrates and commits on `main`. Stale patches, changed
requirements, and unexpected files are rejected before integration.

Before worker verification begins, the controller checks that the snapshot has
the dependencies required by every requested recipe. A missing backend virtual
environment or Flutter package configuration produces one actionable preflight
error before any checks run. Install those dependencies in the worker snapshot
or verify in the main copy when isolation is unnecessary. Focused test selectors may use
path and test-selector characters; shell operators are rejected before a recipe
runs.

These lower-level commands are mainly useful for inspecting or recovering work:

```bash
just ai-status
just ai-status garbanzo-abcd
just ai-stop garbanzo-abcd
just ai-resume garbanzo-abcd
```

## Test a fixed preview and give feedback

A preview is an immutable source snapshot tied to one commit. Ask Codex to
create one when a change is automatically verified. You can also create an
archive directly:

```bash
just ai-preview message-retry --revision HEAD
```

Preview states have distinct meanings:

| State | Meaning |
|---|---|
| `created_unverified` | The snapshot exists, but its launch check has not passed |
| `ready_for_testing` | Automated verification passed and the snapshot is ready for you |
| accepted | You tested that exact revision and said it meets the request |

When reporting a problem, name the preview. This keeps the feedback attached to
the exact source revision rather than whatever happens to be at `HEAD` later:

```bash
just ai-preview message-retry \
  --feedback "Retrying offline still creates two messages" \
  --task-id garbanzo-abcd
```

You can simply tell Codex the same thing in conversation. Codex updates the
affected assignment and keeps unrelated work running. Say that the preview is
accepted only after you have tested the relevant behavior.

## Triage production evidence

Normal `just ai` and `just ai-startup` use fast local startup. Add `--full` when
the task needs current production reports and capacity evidence:

```bash
just ai --full "Investigate the latest production reports"
just ai-startup --full
just ai-triage
just ai-reports list
just ai-incident
```

Scheduled overnight collection remains unchanged. You can request intake at any
time.

`ai-triage` imports reports, CI failures, dependency findings, and secret-scan
findings into the same Beads graph. Raw prompts, emails, traces, response bodies,
and logs stay in private local evidence; public task data contains sanitized
summaries. A production collection failure is reported as a failure, not as an
empty issue list.

Codex may reproduce and prepare a bounded local fix for a clear issue. Production
status changes, rollback, restart, data changes, and deployment remain explicit
actions. A report closes only after its fix is in the deployed revision and its
reported behavior has been verified; a healthy `/health` response is not enough.

## Understand the verification states

Verification follows the risk of the change. Trivial documentation and similarly
low-risk edits need no model review. Routine work gets relevant focused tests or
lint. Substantive work receives one consolidated Sol review after the change is
coherent, followed only by targeted review of material fixes. Run `just check` at
the commit boundary and repeat it only if a later edit changes an input it checks.
The integrated batch runs full `just test` before push or deployment, with real
Docker PostgreSQL migration smoke tests where relevant. A push to `main` starts
CI and does not deploy automatically.

The usual progression is:

1. **Received** — the task has a description and acceptance criteria.
2. **Ready** — dependencies are complete and the scope is clear.
3. **In progress** — a pinned model and source revision own the implementation.
4. **Automatically verified** — the checks and any review required for this change pass.
5. **Ready for your testing** — a fixed preview revision is available.
6. **Accepted** — you tested that revision and approved the behavior.
7. **Deployed** — only after you request `just deploy` or ask Codex to deploy.

For a quick health check of the development tooling itself, run:

```bash
just ai-doctor
just ai-capacity
```

`ai-capacity` is informational during foreground work. The optional overnight
lane stops using a provider at 80% allowance usage and pauses on missing, stale,
or invalid readings. Overnight work is limited to two explicitly safe, small
tasks between midnight and 06:00 America/New_York; it never deploys.

## A practical weekly routine

1. Run `just ai-task summary --limit 10` and choose the highest-impact unblocked item.
2. Adjust its priority and dependencies when production evidence or product
   direction changes.
3. Ask Codex to implement it and provide a stable preview.
4. Test that preview and report feedback using its name.
5. Mark it accepted when the requested behavior works.
6. Ask for deployment only when the accepted batch should reach production.
7. Re-run triage after deployment so linked reports can be behavior-verified and
   closed against the exact deployed revision.

Do not edit `TASKS.md` directly. It is a generated view of Beads; ask Codex or use
the `just ai-task` commands to change work, then let the workflow export the view.
