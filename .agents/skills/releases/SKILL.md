---
name: releases
description: Prepare and execute explicitly requested releases and report-specific delivery verification.
---

Read deploy/AGENTS.md and deploy/README.md. Deploy only when requested; preserve
signing keys, versioning, annotated tags, explicit just deploy and desktop assets.
Use the sequential procedure below; routine deployment is execution, not a new
investigation. Use one writer lock with
integration; never package uncommitted source accidentally. Release evidence
must distinguish the built source revision from the later version-bump commit.
Changelog generation uses Codex from sanitized commit/task information with a
deterministic fallback. Associate Report-ID trailers; never match report titles
or send raw report diagnostics to the changelog model.
A healthy /health alone does not close reports. Verify linked behavior on the
actual deployed fix revision, then synchronize exact report IDs with CAS. Failed
deployment/verification leaves reports open/in_progress. Do not notify reporters.

## Sequential execution and stopping rule

1. Confirm the source revision and preserve unrelated edits. Reuse existing
   passing development checks for unchanged inputs. Run `just check` if needed
   at the commit boundary; run the migration smoke gate when migrations changed.
2. Run `just deploy` once. It already runs full `just test` on its exact source
   snapshot, builds web/backend/voice/APK before replacing production, checks
   local and enabled public health, publishes the signed APK, pushes the release
   tag and records source/release evidence. Do not separately repeat these checks
   or run the full suite immediately before it. Investigate a failed step before
   retrying; do not blindly rerun a partly published release.
3. Use an existing focused smoke check only for changed behavior that needs
   runtime verification. Run required report-bound assertions when closing a
   report. Do not invent a production probe for each changed subsystem, inspect
   real accounts, mint tokens, or create one-off evidence scripts just to deploy.
   If behavior cannot be verified, state that limitation and leave reports open.
4. Track the tag's desktop CI with one bounded watcher (for example
   `timeout 1200 gh run watch <run-id> --interval 60 --exit-status`), keeping its
   output in a private log. Use nonblocking tool yields of at most 60 seconds for
   user updates, without separate status/log/API polls while the watcher runs.
   On success, fetch the release assets once and confirm Android/Linux/Windows
   names. On failure, inspect the failed job; on timeout, report desktop pending.
5. Update the existing deployment evidence once with final smoke/asset status.
   Keep raw logs private; do not duplicate evidence into multiple summaries or
   repeatedly rewrite task descriptions. Stop after required checks pass and
   report the live version, release link and any unresolved limitation.

Express predictable steps, waits, assertions and evidence updates in sequential
shell/Python or tool orchestration, invoked through `just` where required. Keep
full logs on disk and return only exit status, concise results and failure tails
to the model. Do not use repeated model turns to drive a routine polling loop.
Broaden verification only for a failed check, changed input, explicit acceptance
criterion or a concrete unresolved risk; finish once that condition is resolved.
